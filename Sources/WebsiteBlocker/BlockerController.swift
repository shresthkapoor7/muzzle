import AppKit
import Combine
import Foundation

@MainActor
final class BlockerController: ObservableObject {
    @Published private(set) var blockedDomains: [String] = []
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage = "No websites are blocked yet."
    @Published private(set) var lastErrorMessage: String?

    private let domainStore = DomainStore()
    private let systemConfigurationController = SystemConfigurationController()

    func load() throws {
        blockedDomains = try domainStore.load()
        refreshStatus()
    }

    func add(_ rawValue: String) {
        do {
            let domain = try DomainValidator.normalizedDomain(from: rawValue)
            guard !blockedDomains.contains(domain) else {
                statusMessage = "\(domain) is already blocked."
                return
            }

            let previousDomains = blockedDomains
            blockedDomains.append(domain)
            blockedDomains.sort()
            try persistAndApply(revertingTo: previousDomains)
        } catch {
            present(error: error)
        }
    }

    func reconcileHostsFile() throws {
        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply(blockedDomains)
        refreshStatus()
    }

    func endProtection() throws {
        isApplying = true
        defer { isApplying = false }
        try systemConfigurationController.apply([])
        blockedDomains = []
        try domainStore.save([])
        refreshStatus()
    }

    func present(error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = "Action could not be completed."
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func persistAndApply(revertingTo previousDomains: [String]) throws {
        isApplying = true
        defer { isApplying = false }

        do {
            try systemConfigurationController.apply(blockedDomains)
            try domainStore.save(blockedDomains)
            refreshStatus()
        } catch {
            if previousDomains.isEmpty {
                try? systemConfigurationController.apply([])
            } else {
                try? systemConfigurationController.apply(previousDomains)
            }
            blockedDomains = previousDomains
            throw error
        }
    }

    private func refreshStatus() {
        statusMessage = blockedDomains.isEmpty
            ? "No websites are blocked yet."
            : "Blocking \(blockedDomains.count) \(blockedDomains.count == 1 ? "website" : "websites") on this Mac."
    }
}
