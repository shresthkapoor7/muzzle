import AppKit
import Combine
import Foundation

@MainActor
final class BlockerController: ObservableObject {
    private struct SessionState {
        let domains: [String]
        let timedSession: TimedSessionTiming?
        let bypassSession: BypassSessionTiming?
        let remainingBypasses: Int?
    }

    private struct PendingSystemUpdate {
        let state: SessionState
        let outcome: SystemUpdateRetryOutcome
    }

    @Published private(set) var blockedDomains: [String] = []
    @Published private(set) var timedSessionStartDate: Date?
    @Published private(set) var timedSessionEndDate: Date?
    @Published private(set) var timedProgress: Double = 0
    @Published private(set) var bypassSessionStartDate: Date?
    @Published private(set) var bypassEndDate: Date?
    @Published private(set) var bypassProgress: Double = 0
    @Published private(set) var remainingBypasses = 0
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage = "No websites are blocked yet."
    @Published private(set) var lastErrorMessage: String?

    private let domainStore = DomainStore()
    private let timedSessionStore = TimedSessionStore()
    private let bypassSessionStore = BypassSessionStore()
    private let bypassAllowanceStore = BypassAllowanceStore()
    private let systemConfigurationController = SystemConfigurationController()
    private var expiryTimer: Timer?
    private var progressTimer: Timer?
    private var bypassTimer: Timer?
    private var needsExpiredSessionCleanup = false
    private var pendingSystemUpdate: PendingSystemUpdate?

    var isTimedSession: Bool { timedSessionEndDate != nil }
    var isBypassActive: Bool { bypassEndDate != nil }
    var isProtectionEnforced: Bool { !blockedDomains.isEmpty && !isBypassActive }
    var canQuit: Bool { blockedDomains.isEmpty && !isBypassActive }
    var canStartBypass: Bool { !blockedDomains.isEmpty && !isBypassActive && remainingBypasses > 0 }
    var needsSystemReconciliation: Bool { !blockedDomains.isEmpty || needsExpiredSessionCleanup }
    var canRetrySystemUpdate: Bool { pendingSystemUpdate != nil }

    func load() throws {
        blockedDomains = try domainStore.load()
        let timedSession = try timedSessionStore.load()
        timedSessionStartDate = timedSession?.startedAt
        timedSessionEndDate = timedSession?.endsAt
        let bypassSession = try bypassSessionStore.load()
        bypassSessionStartDate = bypassSession?.startedAt
        bypassEndDate = bypassSession?.endsAt
        let storedBypassAllowance = try bypassAllowanceStore.load()

        if let timedSessionEndDate, timedSessionEndDate <= Date() {
            needsExpiredSessionCleanup = !blockedDomains.isEmpty
            blockedDomains = []
            self.timedSessionStartDate = nil
            self.timedSessionEndDate = nil
            bypassSessionStartDate = nil
            bypassEndDate = nil
            bypassProgress = 0
            remainingBypasses = 0
            try domainStore.save([])
            try timedSessionStore.clear()
            try bypassSessionStore.clear()
            try bypassAllowanceStore.clear()
        } else if blockedDomains.isEmpty {
            self.timedSessionEndDate = nil
            self.timedSessionStartDate = nil
            self.bypassSessionStartDate = nil
            self.bypassEndDate = nil
            self.bypassProgress = 0
            remainingBypasses = 0
            try timedSessionStore.clear()
            try bypassSessionStore.clear()
            try bypassAllowanceStore.clear()
        } else {
            if let bypassEndDate, bypassEndDate <= Date() {
                self.bypassSessionStartDate = nil
                self.bypassEndDate = nil
                self.bypassProgress = 0
                try bypassSessionStore.clear()
            }
            let defaultAllowance = bypassEndDate == nil ? 1 : 0
            remainingBypasses = min(max(storedBypassAllowance ?? defaultAllowance, 0), 3)
        }

        scheduleExpiryTimer()
        scheduleProgressTimer()
        scheduleBypassTimer()
        refreshStatus()
    }

    func add(
        _ rawValue: String,
        timedDurationMinutes: Int? = nil,
        allowedBypasses: Int = 1
    ) {
        do {
            let domain = try DomainValidator.normalizedDomain(from: rawValue)
            guard !blockedDomains.contains(domain) else {
                statusMessage = "\(domain) is already blocked."
                return
            }
            if blockedDomains.isEmpty {
                guard (0...3).contains(allowedBypasses) else {
                    throw BlockerError.invalidBypassAllowance
                }
            }
            let timedDurationSeconds: Int?
            if blockedDomains.isEmpty, let timedDurationMinutes {
                guard let seconds = DurationValidator.seconds(for: timedDurationMinutes) else {
                    throw BlockerError.invalidBlockDuration
                }
                timedDurationSeconds = seconds
            } else {
                timedDurationSeconds = nil
            }

            let previousState = currentSessionState
            blockedDomains.append(domain)
            blockedDomains.sort()
            if previousState.domains.isEmpty, let timedDurationSeconds {
                let startDate = Date()
                timedSessionStartDate = startDate
                timedSessionEndDate = startDate.addingTimeInterval(TimeInterval(timedDurationSeconds))
            }
            if previousState.domains.isEmpty {
                remainingBypasses = allowedBypasses
            }
            pendingSystemUpdate = PendingSystemUpdate(
                state: currentSessionState,
                outcome: previousState.domains.isEmpty
                    ? .protectionStarted(isTimed: timedSessionEndDate != nil)
                    : .none
            )
            try persistAndApply(
                revertingTo: previousState
            )
            pendingSystemUpdate = nil
        } catch {
            present(error: error)
        }
    }

    func reconcileSystemState() throws {
        isApplying = true
        defer { isApplying = false }

        if needsExpiredSessionCleanup {
            try systemConfigurationController.apply([])
            needsExpiredSessionCleanup = false
        } else if isBypassActive {
            try systemConfigurationController.apply([])
        } else {
            try systemConfigurationController.apply(blockedDomains)
        }
        refreshStatus()
    }

    func endProtection() throws {
        let previousState = currentSessionState
        let endedState = SessionState(
            domains: [],
            timedSession: nil,
            bypassSession: nil,
            remainingBypasses: nil
        )
        pendingSystemUpdate = PendingSystemUpdate(state: endedState, outcome: .none)
        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply([])
        blockedDomains = []
        timedSessionStartDate = nil
        timedSessionEndDate = nil
        timedProgress = 0
        bypassSessionStartDate = nil
        bypassEndDate = nil
        bypassProgress = 0
        remainingBypasses = 0
        do {
            try persistCurrentSessionState()
        } catch {
            restoreInMemoryState(previousState)
            try? applySystemState(previousState)
            throw error
        }
        pendingSystemUpdate = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        bypassTimer?.invalidate()
        bypassTimer = nil
        refreshStatus()
    }

    func startBypass(for minutes: Int) throws {
        guard minutes > 0 else { throw BlockerError.invalidBypassDuration }
        guard !blockedDomains.isEmpty else { throw BlockerError.noProtectedWebsites }
        guard !isBypassActive else { throw BlockerError.bypassAlreadyActive }
        guard remainingBypasses > 0 else { throw BlockerError.noBypassesRemaining }
        guard let durationSeconds = DurationValidator.seconds(for: minutes) else {
            throw BlockerError.invalidBypassDuration
        }

        let previousState = currentSessionState
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(durationSeconds))
        let bypassState = SessionState(
            domains: previousState.domains,
            timedSession: previousState.timedSession,
            bypassSession: BypassSessionTiming(startedAt: startDate, endsAt: endDate),
            remainingBypasses: max((previousState.remainingBypasses ?? 0) - 1, 0)
        )
        pendingSystemUpdate = PendingSystemUpdate(
            state: bypassState,
            outcome: .bypassStarted(minutes: minutes, isTimed: previousState.timedSession != nil)
        )
        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply([])
        do {
            restoreInMemoryState(bypassState)
            try persistCurrentSessionState()
            scheduleProgressTimer()
            scheduleBypassTimer()
            refreshStatus()
            pendingSystemUpdate = nil
        } catch let persistenceError {
            restoreInMemoryState(previousState)
            do {
                try applySystemState(previousState)
            } catch let systemRestorationError {
                throw BypassPersistenceRollbackError(
                    persistenceError: persistenceError,
                    systemRestorationError: systemRestorationError
                )
            }
            throw persistenceError
        }
    }

    @discardableResult
    func retryPendingSystemUpdate() -> SystemUpdateRetryOutcome {
        guard let pendingSystemUpdate else { return .none }

        let previousState = currentSessionState
        let outcome = pendingSystemUpdate.outcome
        var targetState = pendingSystemUpdate.state
        if case let .bypassStarted(minutes, _) = pendingSystemUpdate.outcome,
           let durationSeconds = DurationValidator.seconds(for: minutes) {
            let startDate = Date()
            targetState = SessionState(
                domains: targetState.domains,
                timedSession: targetState.timedSession,
                bypassSession: BypassSessionTiming(
                    startedAt: startDate,
                    endsAt: startDate.addingTimeInterval(TimeInterval(durationSeconds))
                ),
                remainingBypasses: targetState.remainingBypasses
            )
        }
        if let timedSession = targetState.timedSession, timedSession.endsAt <= Date() {
            targetState = SessionState(
                domains: [],
                timedSession: nil,
                bypassSession: nil,
                remainingBypasses: nil
            )
        }

        isApplying = true
        defer { isApplying = false }
        var didApplyTargetState = false
        do {
            try applySystemState(targetState)
            didApplyTargetState = true
            try persistSessionState(targetState)
            restoreInMemoryState(targetState)
            scheduleExpiryTimer()
            scheduleProgressTimer()
            scheduleBypassTimer()
            refreshStatus()
            self.pendingSystemUpdate = nil
            clearError()
            return targetState.domains.isEmpty ? .none : outcome
        } catch {
            restoreInMemoryState(previousState)
            if didApplyTargetState {
                do {
                    try applySystemState(previousState)
                } catch let systemRestorationError {
                    present(error: SystemUpdateRetryRollbackError(
                        updateError: error,
                        systemRestorationError: systemRestorationError
                    ))
                    return .none
                }
            }
            present(error: error)
            return .none
        }
    }

    func present(error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = "Action could not be completed."
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func persistAndApply(
        revertingTo previousState: SessionState
    ) throws {
        isApplying = true
        defer { isApplying = false }

        do {
            if !isBypassActive {
                try systemConfigurationController.apply(blockedDomains)
            }
            try persistCurrentSessionState()
            scheduleExpiryTimer()
            scheduleProgressTimer()
            refreshStatus()
        } catch {
            if !isBypassActive {
                try? applySystemState(previousState)
            }
            restoreInMemoryState(previousState)
            scheduleExpiryTimer()
            scheduleProgressTimer()
            throw error
        }
    }

    private var currentSessionState: SessionState {
        SessionState(
            domains: blockedDomains,
            timedSession: timedSessionEndDate.map {
                TimedSessionTiming(startedAt: timedSessionStartDate, endsAt: $0)
            },
            bypassSession: bypassEndDate.map {
                BypassSessionTiming(startedAt: bypassSessionStartDate, endsAt: $0)
            },
            remainingBypasses: blockedDomains.isEmpty ? nil : remainingBypasses
        )
    }

    private func persistCurrentSessionState() throws {
        try persistSessionState(currentSessionState)
    }

    private func persistSessionState(_ state: SessionState) throws {
        let previousState = try persistedSessionState()
        do {
            try writePersistedSessionState(state)
        } catch {
            try? writePersistedSessionState(previousState)
            throw error
        }
    }

    private func persistedSessionState() throws -> SessionState {
        let domains = try domainStore.load()
        let timedSession = try timedSessionStore.load()
        let bypassSession = try bypassSessionStore.load()
        let remainingBypasses = try bypassAllowanceStore.load()
        return SessionState(
            domains: domains,
            timedSession: timedSession,
            bypassSession: bypassSession,
            remainingBypasses: remainingBypasses
        )
    }

    private func writePersistedSessionState(_ state: SessionState) throws {
        try domainStore.save(state.domains)
        if let timedSession = state.timedSession {
            try timedSessionStore.save(startedAt: timedSession.startedAt, endsAt: timedSession.endsAt)
        } else {
            try timedSessionStore.clear()
        }
        if let bypassSession = state.bypassSession {
            try bypassSessionStore.save(startedAt: bypassSession.startedAt, endsAt: bypassSession.endsAt)
        } else {
            try bypassSessionStore.clear()
        }
        if let remainingBypasses = state.remainingBypasses {
            try bypassAllowanceStore.save(remaining: remainingBypasses)
        } else {
            try bypassAllowanceStore.clear()
        }
    }

    private func restoreInMemoryState(_ state: SessionState) {
        blockedDomains = state.domains
        timedSessionStartDate = state.timedSession?.startedAt
        timedSessionEndDate = state.timedSession?.endsAt
        timedProgress = 0
        bypassSessionStartDate = state.bypassSession?.startedAt
        bypassEndDate = state.bypassSession?.endsAt
        bypassProgress = 0
        remainingBypasses = state.remainingBypasses ?? 0
    }

    private func applySystemState(_ state: SessionState) throws {
        try systemConfigurationController.apply(state.bypassSession == nil ? state.domains : [])
    }

    private func refreshStatus() {
        guard !blockedDomains.isEmpty else {
            statusMessage = "No websites are blocked yet."
            return
        }

        let count = "Blocking \(blockedDomains.count) \(blockedDomains.count == 1 ? "website" : "websites")"
        let allowance = "\(remainingBypasses) \(remainingBypasses == 1 ? "bypass" : "bypasses") left"
        if let bypassEndDate {
            statusMessage = "Bypass active until \(formattedTime(bypassEndDate)). \(allowance)."
            return
        }
        if let timedSessionEndDate {
            statusMessage = "\(count) until \(formattedTime(timedSessionEndDate)). \(allowance)."
        } else {
            statusMessage = "\(count) on this Mac. \(allowance)."
        }
    }

    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let timedSessionEndDate else { return }
        let interval = timedSessionEndDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        expiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.expireTimedProtection()
            }
        }
    }

    private func scheduleProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        updateTimerProgress()

        let hasTimedProgress = !isBypassActive
            && timedSessionStartDate != nil
            && timedSessionEndDate != nil
        let hasBypassProgress = bypassSessionStartDate != nil && bypassEndDate != nil
        guard hasTimedProgress || hasBypassProgress else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimerProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func updateTimedProgress() {
        guard !isBypassActive,
              let timedSessionStartDate,
              let timedSessionEndDate else {
            timedProgress = 0
            return
        }

        timedProgress = TimerProgress.minuteStep(
            startedAt: timedSessionStartDate,
            endsAt: timedSessionEndDate
        )
    }

    private func updateBypassProgress() {
        guard let bypassSessionStartDate,
              let bypassEndDate else {
            bypassProgress = 0
            return
        }
        bypassProgress = TimerProgress.minuteStep(
            startedAt: bypassSessionStartDate,
            endsAt: bypassEndDate
        )
    }

    private func updateTimerProgress() {
        updateTimedProgress()
        updateBypassProgress()
    }

    private func expireTimedProtection() {
        do {
            try endProtection()
        } catch {
            present(error: error)
        }
    }

    private func scheduleBypassTimer() {
        bypassTimer?.invalidate()
        bypassTimer = nil

        guard let bypassEndDate else { return }
        let interval = bypassEndDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        bypassTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.expireBypass()
            }
        }
    }

    private func expireBypass() {
        do {
            if let timedSessionEndDate, timedSessionEndDate <= Date() {
                try endProtection()
                return
            }

            let previousState = currentSessionState
            let restoredState = SessionState(
                domains: blockedDomains,
                timedSession: timedSessionEndDate.map {
                    TimedSessionTiming(startedAt: timedSessionStartDate, endsAt: $0)
                },
                bypassSession: nil,
                remainingBypasses: remainingBypasses
            )
            pendingSystemUpdate = PendingSystemUpdate(state: restoredState, outcome: .none)
            isApplying = true
            defer { isApplying = false }
            try applySystemState(restoredState)
            do {
                try persistSessionState(restoredState)
                restoreInMemoryState(restoredState)
            } catch let persistenceError {
                restoreInMemoryState(previousState)
                do {
                    try applySystemState(previousState)
                } catch let systemRestorationError {
                    throw BypassPersistenceRollbackError(
                        persistenceError: persistenceError,
                        systemRestorationError: systemRestorationError
                    )
                }
                throw persistenceError
            }
            bypassTimer?.invalidate()
            bypassTimer = nil
            scheduleProgressTimer()
            refreshStatus()
            pendingSystemUpdate = nil
        } catch {
            present(error: error)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

enum DurationValidator {
    static func seconds(for minutes: Int) -> Int? {
        guard minutes > 0 else { return nil }
        let result = minutes.multipliedReportingOverflow(by: 60)
        return result.overflow ? nil : result.partialValue
    }
}

enum SystemUpdateRetryOutcome {
    case none
    case protectionStarted(isTimed: Bool)
    case bypassStarted(minutes: Int, isTimed: Bool)
}

enum TimerProgress {
    static func minuteStep(startedAt: Date, endsAt: Date, now: Date = Date()) -> Double {
        let totalMinutes = max(1, Int(ceil(endsAt.timeIntervalSince(startedAt) / 60)))
        let completedMinutes = max(0, Int(floor(now.timeIntervalSince(startedAt) / 60)))
        return min(Double(completedMinutes) / Double(totalMinutes), 1)
    }
}

private struct BypassPersistenceRollbackError: LocalizedError {
    let persistenceError: Error
    let systemRestorationError: Error

    var errorDescription: String? {
        "Muzzle could not save the bypass session, and it could not restore the website block. "
            + "Save error: \(persistenceError.localizedDescription). "
            + "Restore error: \(systemRestorationError.localizedDescription)."
    }
}

private struct SystemUpdateRetryRollbackError: LocalizedError {
    let updateError: Error
    let systemRestorationError: Error

    var errorDescription: String? {
        "Muzzle could not complete the retried update, and it could not restore the previous website rules. "
            + "Update error: \(updateError.localizedDescription). "
            + "Restore error: \(systemRestorationError.localizedDescription)."
    }
}

private enum BlockerError: LocalizedError {
    case invalidBlockDuration
    case invalidBypassDuration
    case invalidBypassAllowance
    case noProtectedWebsites
    case bypassAlreadyActive
    case noBypassesRemaining

    var errorDescription: String? {
        switch self {
        case .invalidBlockDuration:
            "Enter a positive block duration."
        case .invalidBypassDuration:
            "Enter a positive bypass duration."
        case .invalidBypassAllowance:
            "Choose between zero and three bypasses."
        case .noProtectedWebsites:
            "Add a website before starting a bypass."
        case .bypassAlreadyActive:
            "A bypass is already active."
        case .noBypassesRemaining:
            "No bypasses remain for this session."
        }
    }
}
