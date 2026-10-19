import Foundation
import Combine

@MainActor
final class SavedWebsites: ObservableObject {
    @Published private(set) var domains: [String]
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, isDebugMode: Bool = DebugMode.isEnabled) {
        self.defaults = defaults
        key = isDebugMode ? "MuzzleDebugSavedWebsites" : "MuzzleSavedWebsites"
        domains = Array(Set((defaults.stringArray(forKey: key) ?? []).compactMap {
            try? DomainValidator.normalizedDomain(from: $0)
        })).sorted()
    }

    func add(_ input: String) throws {
        let domain = try DomainValidator.normalizedDomain(from: input)
        domains = Array(Set(domains + [domain])).sorted()
        defaults.set(domains, forKey: key)
    }

    func remove(_ domain: String) {
        domains.removeAll { $0 == domain }
        defaults.set(domains, forKey: key)
    }
}
