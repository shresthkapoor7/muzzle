import Foundation

struct TimedSessionStore {
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
            return directory.appendingPathComponent("timed-session.json")
        }
    }

    func load() throws -> Date? {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(TimedSession.self, from: Data(contentsOf: url)).endsAt
    }

    func save(endsAt: Date) throws {
        let data = try JSONEncoder().encode(TimedSession(endsAt: endsAt))
        try data.write(to: try storeURL, options: .atomic)
    }

    func clear() throws {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private struct TimedSession: Codable {
    let endsAt: Date
}
