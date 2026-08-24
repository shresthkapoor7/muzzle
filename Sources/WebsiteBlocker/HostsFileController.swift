import Foundation

struct HostsFileController {
    private let fileManager = FileManager.default
    private let hostsURL = URL(fileURLWithPath: "/etc/hosts")
    private let openingMarker = "# WEBSITE_BLOCKER_BEGIN — managed by Website Blocker"
    private let closingMarker = "# WEBSITE_BLOCKER_END"

    enum HostsError: LocalizedError {
        case noHostsFile
        case privilegeCommandFailed(String)
        case unreadableHostsFile

        var errorDescription: String? {
            switch self {
            case .noHostsFile:
                "macOS’s hosts file could not be found."
            case .privilegeCommandFailed(let details):
                "macOS did not update the hosts file. \(details)"
            case .unreadableHostsFile:
                "macOS’s hosts file could not be read as UTF-8 text."
            }
        }
    }

    func apply(_ domains: [String]) throws {
        let stagingURL = try makeStagingFile(for: domains)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try copyWithAdministratorPrivileges(command: installCommand(from: stagingURL))
    }

    func makeStagingFile(for domains: [String]) throws -> URL {
        guard fileManager.fileExists(atPath: hostsURL.path) else { throw HostsError.noHostsFile }
        guard let existingContents = try? String(contentsOf: hostsURL, encoding: .utf8) else {
            throw HostsError.unreadableHostsFile
        }

        var output = removeManagedBlock(from: existingContents)
            .trimmingCharacters(in: .newlines)

        if !domains.isEmpty {
            let entries = domains.flatMap { domain in
                ["127.0.0.1 \(domain)", "127.0.0.1 www.\(domain)", "::1 \(domain)", "::1 www.\(domain)"]
            }
            output += "\n\n\(openingMarker)\n"
            output += "# These entries are intentionally managed by the menu-bar app.\n"
            output += entries.joined(separator: "\n")
            output += "\n\(closingMarker)"
        }
        output += "\n"

        return try makeStagingFile(contents: output)
    }

    func installCommand(from stagingURL: URL) -> String {
        let quotedStagingPath = shellQuote(stagingURL.path)
        return "/usr/bin/install -m 644 \(quotedStagingPath) /etc/hosts && /usr/bin/dscacheutil -flushcache && (/usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true)"
    }

    private func removeManagedBlock(from contents: String) -> String {
        guard let start = contents.range(of: openingMarker),
              let end = contents.range(of: closingMarker, range: start.upperBound..<contents.endIndex) else {
            return contents
        }
        var result = contents
        result.removeSubrange(start.lowerBound..<end.upperBound)
        return result
    }

    private func makeStagingFile(contents: String) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WebsiteBlocker", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)

        let stagingURL = base.appendingPathComponent("hosts.staging")
        try contents.data(using: .utf8)?.write(to: stagingURL, options: .atomic)
        return stagingURL
    }

    private func copyWithAdministratorPrivileges(command: String) throws {
        let source = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let details = error[NSAppleScript.errorMessage] as? String ?? "Administrator access was cancelled or denied."
            throw HostsError.privilegeCommandFailed(details)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
