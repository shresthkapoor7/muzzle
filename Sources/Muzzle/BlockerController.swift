import AppKit
import Combine
import Foundation

@MainActor
final class BlockerController: ObservableObject {
    @Published private(set) var blockedDomains: [String] = []
    @Published private(set) var timedSessionEndDate: Date?
    @Published private(set) var bypassEndDate: Date?
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage = "No websites are blocked yet."
    @Published private(set) var lastErrorMessage: String?

    private let domainStore = DomainStore()
    private let timedSessionStore = TimedSessionStore()
    private let bypassSessionStore = BypassSessionStore()
    private let systemConfigurationController = SystemConfigurationController()
    private var expiryTimer: Timer?
    private var bypassTimer: Timer?
    private var needsExpiredSessionCleanup = false

    var isTimedSession: Bool { timedSessionEndDate != nil }
    var isBypassActive: Bool { bypassEndDate != nil }
    var isProtectionEnforced: Bool { !blockedDomains.isEmpty && !isBypassActive }
    var canQuit: Bool { blockedDomains.isEmpty && !isBypassActive }
    var needsSystemReconciliation: Bool { !blockedDomains.isEmpty || needsExpiredSessionCleanup }

    func load() throws {
        blockedDomains = try domainStore.load()
        timedSessionEndDate = try timedSessionStore.load()
        bypassEndDate = try bypassSessionStore.load()

        if let timedSessionEndDate, timedSessionEndDate <= Date() {
            needsExpiredSessionCleanup = !blockedDomains.isEmpty
            blockedDomains = []
            self.timedSessionEndDate = nil
            bypassEndDate = nil
            try domainStore.save([])
            try timedSessionStore.clear()
            try bypassSessionStore.clear()
        } else if blockedDomains.isEmpty, timedSessionEndDate != nil {
            self.timedSessionEndDate = nil
            try timedSessionStore.clear()
        } else if blockedDomains.isEmpty, bypassEndDate != nil {
            self.bypassEndDate = nil
            try bypassSessionStore.clear()
        } else if let bypassEndDate, bypassEndDate <= Date() {
            self.bypassEndDate = nil
            try bypassSessionStore.clear()
        }

        scheduleExpiryTimer()
        scheduleBypassTimer()
        refreshStatus()
    }

    func add(_ rawValue: String, timedDurationMinutes: Int? = nil) {
        do {
            guard !isBypassActive else {
                statusMessage = "End the bypass before changing protected websites."
                return
            }
            let domain = try DomainValidator.normalizedDomain(from: rawValue)
            guard !blockedDomains.contains(domain) else {
                statusMessage = "\(domain) is already blocked."
                return
            }

            let previousDomains = blockedDomains
            let previousTimedSessionEndDate = timedSessionEndDate
            blockedDomains.append(domain)
            blockedDomains.sort()
            if previousDomains.isEmpty, let timedDurationMinutes {
                timedSessionEndDate = Date().addingTimeInterval(TimeInterval(timedDurationMinutes * 60))
            }
            try persistAndApply(
                revertingTo: previousDomains,
                previousTimedSessionEndDate: previousTimedSessionEndDate
            )
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
        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply([])
        blockedDomains = []
        timedSessionEndDate = nil
        bypassEndDate = nil
        try domainStore.save([])
        try timedSessionStore.clear()
        try bypassSessionStore.clear()
        expiryTimer?.invalidate()
        expiryTimer = nil
        bypassTimer?.invalidate()
        bypassTimer = nil
        refreshStatus()
    }

    func startBypass(for minutes: Int) throws {
        guard minutes > 0 else { throw BlockerError.invalidBypassDuration }
        guard !blockedDomains.isEmpty else { throw BlockerError.noProtectedWebsites }
        guard !isBypassActive else { throw BlockerError.bypassAlreadyActive }

        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply([])
        do {
            let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            try bypassSessionStore.save(endsAt: endDate)
            bypassEndDate = endDate
            scheduleBypassTimer()
            refreshStatus()
        } catch {
            try? systemConfigurationController.apply(blockedDomains)
            throw error
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
        revertingTo previousDomains: [String],
        previousTimedSessionEndDate: Date?
    ) throws {
        isApplying = true
        defer { isApplying = false }

        do {
            try systemConfigurationController.apply(blockedDomains)
            try domainStore.save(blockedDomains)
            if let timedSessionEndDate {
                try timedSessionStore.save(endsAt: timedSessionEndDate)
            } else {
                try timedSessionStore.clear()
            }
            scheduleExpiryTimer()
            refreshStatus()
        } catch {
            if previousDomains.isEmpty {
                try? systemConfigurationController.apply([])
            } else {
                try? systemConfigurationController.apply(previousDomains)
            }
            blockedDomains = previousDomains
            timedSessionEndDate = previousTimedSessionEndDate
            scheduleExpiryTimer()
            throw error
        }
    }

    private func refreshStatus() {
        guard !blockedDomains.isEmpty else {
            statusMessage = "No websites are blocked yet."
            return
        }

        let count = "Blocking \(blockedDomains.count) \(blockedDomains.count == 1 ? "website" : "websites")"
        if let bypassEndDate {
            statusMessage = "Bypass active until \(formattedTime(bypassEndDate))."
            return
        }
        if let timedSessionEndDate {
            statusMessage = "\(count) until \(formattedTime(timedSessionEndDate))."
        } else {
            statusMessage = "\(count) on this Mac."
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

            isApplying = true
            defer { isApplying = false }
            try systemConfigurationController.apply(blockedDomains)
            try bypassSessionStore.clear()
            bypassEndDate = nil
            bypassTimer?.invalidate()
            bypassTimer = nil
            refreshStatus()
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

private enum BlockerError: LocalizedError {
    case invalidBypassDuration
    case noProtectedWebsites
    case bypassAlreadyActive

    var errorDescription: String? {
        switch self {
        case .invalidBypassDuration:
            "Enter a positive bypass duration."
        case .noProtectedWebsites:
            "Add a website before starting a bypass."
        case .bypassAlreadyActive:
            "A bypass is already active."
        }
    }
}
