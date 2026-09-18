import Foundation

struct BypassAllowanceStore {
    private let fileManager = FileManager.default
    private let applicationSupportDirectoryName: String

    init(applicationSupportDirectoryName: String = "Muzzle") {
        self.applicationSupportDirectoryName = applicationSupportDirectoryName
    }

    private var storeURL: URL {
        get throws {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("bypass-allowance.json")
        }
    }

    func load() throws -> BypassAllowance? {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(BypassAllowance.self, from: Data(contentsOf: url))
    }

    func save(_ allowance: BypassAllowance) throws {
        let data = try JSONEncoder().encode(allowance)
        try data.write(to: try storeURL, options: .atomic)
    }

    func clear() throws {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

struct BypassAllowance: Codable, Equatable {
    var remaining: Int
    let dailyLimit: Int
    private(set) var renewsAt: Date
    static let renewalInterval: TimeInterval = 24 * 60 * 60

    init(limit: Int, now: Date = Date()) {
        dailyLimit = min(max(limit, 0), 3)
        remaining = dailyLimit
        renewsAt = now.addingTimeInterval(Self.renewalInterval)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        remaining = min(max(try values.decode(Int.self, forKey: .remaining), 0), 3)
        // Legacy data cannot distinguish a depleted allowance from a zero-bypass session.
        dailyLimit = min(max(try values.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? remaining, 0), 3)
        renewsAt = try values.decodeIfPresent(Date.self, forKey: .renewsAt)
            ?? Date().addingTimeInterval(Self.renewalInterval)
    }

    @discardableResult
    mutating func renewIfNeeded(now: Date = Date()) -> Bool {
        guard now >= renewsAt else { return false }
        let periods = floor(now.timeIntervalSince(renewsAt) / Self.renewalInterval) + 1
        renewsAt = renewsAt.addingTimeInterval(periods * Self.renewalInterval)
        remaining = dailyLimit
        return true
    }

    func consumingOne() -> Self {
        var copy = self
        copy.remaining = max(remaining - 1, 0)
        return copy
    }

    func grantingOne() -> Self {
        var copy = self
        copy.remaining = min(remaining + 1, 3)
        return copy
    }
}
