import Foundation

struct BypassAllowanceStore {
    private let fileManager = FileManager.default

    private var storeURL: URL {
        get throws {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("Muzzle", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("bypass-allowance.json")
        }
    }

    func load() throws -> Int? {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(BypassAllowance.self, from: Data(contentsOf: url)).remaining
    }

    func save(remaining: Int) throws {
        let data = try JSONEncoder().encode(BypassAllowance(remaining: remaining))
        try data.write(to: try storeURL, options: .atomic)
    }

    func clear() throws {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private struct BypassAllowance: Codable {
    let remaining: Int
}
