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
    private let hostsFileController = HostsFileController()
    private let packetFilterController = PacketFilterController()

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
        try packetFilterController.apply(blockedDomains)
        try hostsFileController.apply(blockedDomains)
        refreshStatus()
    }

    func endProtection() throws {
        isApplying = true
        defer { isApplying = false }
        try packetFilterController.remove()
        try hostsFileController.apply([])
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
            try packetFilterController.apply(blockedDomains)
            try hostsFileController.apply(blockedDomains)
            try domainStore.save(blockedDomains)
            refreshStatus()
        } catch {
            if previousDomains.isEmpty {
                try? packetFilterController.remove()
            } else {
                try? packetFilterController.apply(previousDomains)
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
