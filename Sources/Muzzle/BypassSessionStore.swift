import Foundation

struct BypassSessionStore {
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
            return directory.appendingPathComponent("bypass-session.json")
        }
    }

    func load() throws -> BypassSessionTiming? {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(BypassSession.self, from: Data(contentsOf: url))
        return BypassSessionTiming(startedAt: session.startedAt, endsAt: session.endsAt)
    }

    func save(startedAt: Date?, endsAt: Date) throws {
        let data = try JSONEncoder().encode(BypassSession(startedAt: startedAt, endsAt: endsAt))
        try data.write(to: try storeURL, options: .atomic)
    }

    func clear() throws {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

struct BypassSessionTiming {
    let startedAt: Date?
    let endsAt: Date
}

private struct BypassSession: Codable {
    let startedAt: Date?
    let endsAt: Date
}
