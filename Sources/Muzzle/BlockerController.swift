import AppKit
import Combine
import Foundation

@MainActor
final class BlockerController: ObservableObject {
    @Published private(set) var blockedDomains: [String] = []
    @Published private(set) var timedSessionEndDate: Date?
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage = "No websites are blocked yet."
    @Published private(set) var lastErrorMessage: String?

    private let domainStore = DomainStore()
    private let timedSessionStore = TimedSessionStore()
    private let systemConfigurationController = SystemConfigurationController()
    private var expiryTimer: Timer?
    private var needsExpiredSessionCleanup = false

    var isTimedSession: Bool { timedSessionEndDate != nil }
    var needsSystemReconciliation: Bool { !blockedDomains.isEmpty || needsExpiredSessionCleanup }

    func load() throws {
        blockedDomains = try domainStore.load()
        timedSessionEndDate = try timedSessionStore.load()

        if let timedSessionEndDate, timedSessionEndDate <= Date() {
            needsExpiredSessionCleanup = !blockedDomains.isEmpty
            blockedDomains = []
            self.timedSessionEndDate = nil
            try domainStore.save([])
            try timedSessionStore.clear()
        } else if blockedDomains.isEmpty, timedSessionEndDate != nil {
            self.timedSessionEndDate = nil
            try timedSessionStore.clear()
        }

        scheduleExpiryTimer()
        refreshStatus()
    }

    func add(_ rawValue: String, timedDurationMinutes: Int? = nil) {
        do {
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
        try domainStore.save([])
        try timedSessionStore.clear()
        expiryTimer?.invalidate()
        expiryTimer = nil
        refreshStatus()
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
        if let timedSessionEndDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            statusMessage = "\(count) until \(formatter.string(from: timedSessionEndDate))."
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
}
