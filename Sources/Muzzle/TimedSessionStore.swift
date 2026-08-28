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

    func load() throws -> TimedSessionTiming? {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(TimedSession.self, from: Data(contentsOf: url))
        return TimedSessionTiming(startedAt: session.startedAt, endsAt: session.endsAt)
    }

    func save(startedAt: Date?, endsAt: Date) throws {
        let data = try JSONEncoder().encode(TimedSession(startedAt: startedAt, endsAt: endsAt))
        try data.write(to: try storeURL, options: .atomic)
    }

    func clear() throws {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

struct TimedSessionTiming {
    let startedAt: Date?
    let endsAt: Date
}

private struct TimedSession: Codable {
    let startedAt: Date?
    let endsAt: Date
}
