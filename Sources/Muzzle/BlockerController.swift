import AppKit
import Combine
import Foundation

@MainActor
final class BlockerController: ObservableObject {
    private struct SessionState {
        let domains: [String]
        let timedSession: TimedSessionTiming?
        let bypassSession: BypassSessionTiming?
        let allowance: BypassAllowance?
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
    @Published private var allowance: BypassAllowance?
    var remainingBypasses: Int { allowance?.remaining ?? 0 }
    var bypassRenewalDate: Date? { allowance?.renewsAt }
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage = "No websites are blocked yet."
    @Published private(set) var lastErrorMessage: String?

    private let domainStore: DomainStore
    private let timedSessionStore: TimedSessionStore
    private let bypassSessionStore: BypassSessionStore
    private let bypassAllowanceStore: BypassAllowanceStore
    private let applyConfiguration: ([String]) throws -> Void
    private var expiryTimer: Timer?
    private var progressTimer: Timer?
    private var bypassTimer: Timer?
    private var allowanceTimer: Timer?
    private var needsExpiredSessionCleanup = false
    private var pendingSystemUpdate: PendingSystemUpdate?
    private(set) var sessionID = UUID()
    var onBypassRestoration: ((BypassRestorationEvent) -> Void)?

    var isTimedSession: Bool { timedSessionEndDate != nil }
    var isBypassActive: Bool { bypassEndDate != nil }
    var isProtectionEnforced: Bool { !blockedDomains.isEmpty && !isBypassActive }
    var canQuit: Bool { blockedDomains.isEmpty && !isBypassActive }
    var canStartBypass: Bool { !blockedDomains.isEmpty && !isBypassActive && remainingBypasses > 0 }
    var needsSystemReconciliation: Bool { !blockedDomains.isEmpty || needsExpiredSessionCleanup }
    var canRetrySystemUpdate: Bool { pendingSystemUpdate != nil }

    init(
        isDebugMode: Bool = false,
        applicationSupportDirectoryName: String? = nil,
        applyConfiguration: (([String]) throws -> Void)? = nil
    ) {
        let profile: BlockingProfile = isDebugMode ? .debug : .normal
        let directory = applicationSupportDirectoryName ?? profile.applicationSupportDirectoryName
        domainStore = DomainStore(
            applicationSupportDirectoryName: directory,
            migratesLegacyStore: !isDebugMode && applicationSupportDirectoryName == nil
        )
        timedSessionStore = TimedSessionStore(applicationSupportDirectoryName: directory)
        bypassSessionStore = BypassSessionStore(applicationSupportDirectoryName: directory)
        bypassAllowanceStore = BypassAllowanceStore(applicationSupportDirectoryName: directory)
        self.applyConfiguration = applyConfiguration ?? SystemConfigurationController(profile: profile).apply
    }

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
            allowance = nil
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
            allowance = nil
            try timedSessionStore.clear()
            try bypassSessionStore.clear()
            try bypassAllowanceStore.clear()
        } else {
            // Keep expired bypasses until restoring the system rules succeeds.
            let defaultAllowance = bypassEndDate == nil ? 1 : 0
            allowance = storedBypassAllowance ?? BypassAllowance(limit: defaultAllowance)
            allowance?.renewIfNeeded()
            if let allowance { try bypassAllowanceStore.save(allowance) }
        }

        scheduleExpiryTimer()
        scheduleProgressTimer()
        scheduleBypassTimer()
        scheduleAllowanceTimer()
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
                sessionID = UUID()
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
                allowance = BypassAllowance(limit: allowedBypasses)
            }
            let previousPendingSystemUpdate = pendingSystemUpdate
            pendingSystemUpdate = PendingSystemUpdate(
                state: currentSessionState,
                outcome: previousState.domains.isEmpty
                    ? .protectionStarted(isTimed: timedSessionEndDate != nil)
                    : .none
            )
            try persistAndApply(
                revertingTo: previousState,
                restoringPendingUpdate: previousPendingSystemUpdate
            )
            pendingSystemUpdate = nil
            if let bypassEndDate, bypassEndDate <= Date() {
                try restoreExpiredBypass()
            }
        } catch {
            present(error: error)
        }
    }

    func reconcileSystemState() throws {
        isApplying = true
        defer { isApplying = false }

        if needsExpiredSessionCleanup {
            try applyConfiguration([])
            needsExpiredSessionCleanup = false
        } else if let bypassEndDate, bypassEndDate <= Date() {
            try restoreExpiredBypass()
        } else if isBypassActive {
            try applyConfiguration([])
        } else {
            try applyConfiguration(blockedDomains)
        }
        refreshStatus()
    }

    func endProtection() throws {
        let previousState = currentSessionState
        let endedState = SessionState(
            domains: [],
            timedSession: nil,
            bypassSession: nil,
            allowance: nil
        )
        pendingSystemUpdate = PendingSystemUpdate(state: endedState, outcome: .none)
        isApplying = true
        defer { isApplying = false }
        try applySystemState(endedState)
        blockedDomains = []
        timedSessionStartDate = nil
        timedSessionEndDate = nil
        timedProgress = 0
        bypassSessionStartDate = nil
        bypassEndDate = nil
        bypassProgress = 0
        allowance = nil
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
        allowanceTimer?.invalidate()
        allowanceTimer = nil
        refreshStatus()
    }

    func startBypass(for minutes: Int) throws {
        try renewBypassesIfNeeded()
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
            allowance: previousState.allowance?.consumingOne()
        )
        pendingSystemUpdate = PendingSystemUpdate(
            state: bypassState,
            outcome: .bypassStarted(minutes: minutes, isTimed: previousState.timedSession != nil)
        )
        isApplying = true
        defer { isApplying = false }
        try applySystemState(bypassState)
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

    func grantExtraBypass() throws {
        guard !blockedDomains.isEmpty else { throw BlockerError.noProtectedWebsites }
        try renewBypassesIfNeeded()
        guard remainingBypasses < 3 else { throw BlockerError.bypassAllowanceFull }
        guard let updated = allowance?.grantingOne() else { return }
        try bypassAllowanceStore.save(updated)
        allowance = updated
        if let pending = pendingSystemUpdate, let oldAllowance = pending.state.allowance {
            pendingSystemUpdate = PendingSystemUpdate(
                state: SessionState(domains: pending.state.domains, timedSession: pending.state.timedSession,
                                    bypassSession: pending.state.bypassSession, allowance: oldAllowance.grantingOne()),
                outcome: pending.outcome
            )
        }
        refreshStatus()
    }

    @discardableResult
    func retryPendingSystemUpdate() -> SystemUpdateRetryOutcome {
        do { try renewBypassesIfNeeded() } catch { present(error: error); return .none }
        guard let pendingSystemUpdate else { return .none }

        let previousState = currentSessionState
        let outcome = pendingSystemUpdate.outcome
        var targetState = pendingSystemUpdate.state
        let restoringBypass = bypassEndDate.map { $0 <= Date() } == true
            && targetState.bypassSession == nil && !targetState.domains.isEmpty
        if restoringBypass { onBypassRestoration?(.pending) }
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
                allowance: targetState.allowance
            )
        }
        if let timedSession = targetState.timedSession, timedSession.endsAt <= Date() {
            targetState = SessionState(
                domains: [],
                timedSession: nil,
                bypassSession: nil,
                allowance: nil
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
            if restoringBypass, !targetState.domains.isEmpty { onBypassRestoration?(.restored) }
            return targetState.domains.isEmpty ? .none : outcome
        } catch {
            if restoringBypass { onBypassRestoration?(.failed) }
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
        revertingTo previousState: SessionState,
        restoringPendingUpdate previousPendingSystemUpdate: PendingSystemUpdate?
    ) throws {
        isApplying = true
        defer { isApplying = false }

        do {
            if !isBypassActive {
                try applySystemState(currentSessionState)
            }
            do {
                try persistCurrentSessionState()
            } catch {
                pendingSystemUpdate = previousPendingSystemUpdate
                throw error
            }
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
            allowance: blockedDomains.isEmpty ? nil : allowance
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
        let allowance = try bypassAllowanceStore.load()
        return SessionState(
            domains: domains,
            timedSession: timedSession,
            bypassSession: bypassSession,
            allowance: allowance
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
        if let allowance = state.allowance {
            try bypassAllowanceStore.save(allowance)
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
        allowance = state.allowance
    }

    private func applySystemState(_ state: SessionState) throws {
        try applyConfiguration(state.bypassSession == nil ? state.domains : [])
    }

    private func refreshStatus() {
        guard !blockedDomains.isEmpty else {
            statusMessage = "No websites are blocked yet."
            return
        }

        let count = "Blocking \(blockedDomains.count) \(blockedDomains.count == 1 ? "website" : "websites")"
        let allowance = "\(remainingBypasses) \(remainingBypasses == 1 ? "bypass" : "bypasses") left"
        if let bypassEndDate {
            if bypassEndDate <= Date() {
                statusMessage = "Bypass expired. Restore protection using Retry macOS permission. \(allowance)."
                return
            }
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
        scheduleAllowanceTimer()
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
        guard !isApplying else { return }
        do {
            try restoreExpiredBypass()
        } catch {
            present(error: error)
        }
    }

    private func restoreExpiredBypass() throws {
        guard let bypassEndDate, bypassEndDate <= Date() else { return }
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
                allowance: allowance
            )
            pendingSystemUpdate = PendingSystemUpdate(state: restoredState, outcome: .none)
            // Send before the blocking administrator dialog, including when it is ignored.
            onBypassRestoration?(.pending)
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
            onBypassRestoration?(.restored)
        } catch {
            onBypassRestoration?(.failed)
            throw error
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    func renewBypassesIfNeeded(now: Date = Date()) throws {
        guard !isApplying, !blockedDomains.isEmpty,
              timedSessionEndDate.map({ $0 > now }) ?? true,
              var updated = allowance, updated.renewIfNeeded(now: now) else { return }
        try bypassAllowanceStore.save(updated)
        allowance = updated
        if let pending = pendingSystemUpdate, pending.state.allowance != nil {
            var targetAllowance = updated
            if case .bypassStarted = pending.outcome { targetAllowance = updated.consumingOne() }
            pendingSystemUpdate = PendingSystemUpdate(
                state: SessionState(domains: pending.state.domains, timedSession: pending.state.timedSession,
                                    bypassSession: pending.state.bypassSession, allowance: targetAllowance),
                outcome: pending.outcome
            )
        }
        refreshStatus()
    }

    private func scheduleAllowanceTimer() {
        allowanceTimer?.invalidate()
        allowanceTimer = nil
        guard allowance != nil, !blockedDomains.isEmpty else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                do { try self?.renewBypassesIfNeeded() }
                catch { self?.present(error: error) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        allowanceTimer = timer
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
    case bypassAllowanceFull

    var errorDescription: String? {
        switch self {
        case .bypassAllowanceFull:
            "You already have three bypasses available."
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
