import Foundation

struct DomainStore {
    private let fileManager = FileManager.default

    private var applicationSupportDirectory: URL {
        get throws {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("WebsiteBlocker", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    private var storeURL: URL {
        get throws { try applicationSupportDirectory.appendingPathComponent("blocked-domains.json") }
    }

    func load() throws -> [String] {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String].self, from: data).sorted()
    }

    func save(_ domains: [String]) throws {
        let data = try JSONEncoder().encode(domains.sorted())
        try data.write(to: try storeURL, options: .atomic)
    }
}

enum DomainValidator {
    enum ValidationError: LocalizedError {
        case invalidDomain

        var errorDescription: String? {
            "Enter a domain such as example.com, not a path, search term, or IP address."
        }
    }

    static func normalizedDomain(from rawValue: String) throws -> String {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { throw ValidationError.invalidDomain }

        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let components = URLComponents(string: candidate),
              let rawHost = components.host,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil else {
            throw ValidationError.invalidDomain
        }

        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let looksLikeIPv4Address = labels.count == 4 && labels.allSatisfy { label in
            guard let octet = Int(label), String(octet) == label.description else { return false }
            return (0...255).contains(octet)
        }
        let valid = labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            } && label.first != "-" && label.last != "-"
        }
        guard valid, !looksLikeIPv4Address, host.count <= 253, !host.contains("..") else {
            throw ValidationError.invalidDomain
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
