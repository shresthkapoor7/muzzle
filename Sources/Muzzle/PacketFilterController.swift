import Foundation

struct PacketFilterController {
    private let fileManager = FileManager.default
    private let anchorURL = URL(fileURLWithPath: "/etc/pf.anchors/muzzle")
    private let anchorName = "com.apple/muzzle"
    private let legacyAnchorURL = URL(fileURLWithPath: "/etc/pf.anchors/websiteblocker")
    private let legacyAnchorName = "com.apple/websiteblocker"

    enum PacketFilterError: LocalizedError {
        case noResolvedAddresses
        case privilegeCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .noResolvedAddresses:
                "The website’s public addresses could not be resolved for network-level blocking. Check your network connection and try again."
            case .privilegeCommandFailed(let details):
                "macOS did not update the packet-filter rules. \(details)"
            }
        }
    }

    func makeStagingAnchor(for domains: [String]) throws -> (
        url: URL,
        ipv4Addresses: [String],
        ipv6Addresses: [String]
    ) {
        let addresses = resolveAddresses(for: domains)
        guard !addresses.ipv4.isEmpty || !addresses.ipv6.isEmpty else {
            throw PacketFilterError.noResolvedAddresses
        }
        let anchorRules = rules(ipv4Addresses: addresses.ipv4, ipv6Addresses: addresses.ipv6)
        return (
            url: try makeStagingAnchor(rules: anchorRules),
            ipv4Addresses: addresses.ipv4,
            ipv6Addresses: addresses.ipv6
        )
    }

    func installCommand(anchor: URL, ipv4Addresses: [String], ipv6Addresses: [String]) -> String {
        """
        \(removeLegacyCommand()) && \\
        /usr/bin/install -d -m 755 /etc/pf.anchors && \\
        /usr/bin/install -m 600 \(shellQuote(anchor.path)) \(shellQuote(anchorURL.path)) && \\
        /sbin/pfctl -a \(anchorName) -f \(shellQuote(anchorURL.path)) && \\
        (/sbin/pfctl -e >/dev/null 2>&1 || true) && \\
        \(terminateExistingStatesCommand(ipv4Addresses: ipv4Addresses, ipv6Addresses: ipv6Addresses))
        """
    }

    func terminateExistingStatesCommand(ipv4Addresses: [String], ipv6Addresses: [String]) -> String {
        let ipv4Commands = ipv4Addresses.sorted().map { address in
            "/sbin/pfctl -k 0.0.0.0/0 -k \(shellQuote(address))"
        }
        let ipv6Commands = ipv6Addresses.sorted().map { address in
            "/sbin/pfctl -k ::/0 -k \(shellQuote(address))"
        }
        let commands = ipv4Commands + ipv6Commands
        return commands.isEmpty ? ":" : commands.joined(separator: " && ")
    }

    func removeCommand() -> String {
        """
        (/sbin/pfctl -a \(anchorName) -F all >/dev/null 2>&1 || true) && \\
        /bin/rm -f \(shellQuote(anchorURL.path)) && \\
        \(removeLegacyCommand())
        """
    }

    func rules(ipv4Addresses: [String], ipv6Addresses: [String]) -> String {
        var rules = ["# This anchor is managed by Muzzle. Do not edit while protection is active."]

        if !ipv4Addresses.isEmpty {
            rules.append("table <muzzle_ipv4> persist { \(ipv4Addresses.sorted().joined(separator: ", ")) }")
            rules.append("block return out quick inet to <muzzle_ipv4>")
        }
        if !ipv6Addresses.isEmpty {
            rules.append("table <muzzle_ipv6> persist { \(ipv6Addresses.sorted().joined(separator: ", ")) }")
            rules.append("block return out quick inet6 to <muzzle_ipv6>")
        }

        return rules.joined(separator: "\n") + "\n"
    }

    private func resolveAddresses(for domains: [String]) -> (ipv4: [String], ipv6: [String]) {
        var ipv4 = Set<String>()
        var ipv6 = Set<String>()

        for domain in domains {
            ipv4.formUnion(dnsAnswers(recordType: "A", domain: domain).filter(isIPv4Address))
            ipv6.formUnion(dnsAnswers(recordType: "AAAA", domain: domain).filter(isIPv6Address))
        }
        return (Array(ipv4), Array(ipv6))
    }

    private func dnsAnswers(recordType: String, domain: String) -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        process.arguments = ["+short", recordType, domain]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \ .isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } catch {
            return []
        }
    }

    private func isIPv4Address(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            guard let number = Int(octet), String(number) == octet else { return false }
            return (0...255).contains(number)
        }
    }

    private func isIPv6Address(_ value: String) -> Bool {
        value.contains(":") && value.allSatisfy { character in
            character.isHexDigit || character == ":"
        }
    }

    private func makeStagingAnchor(rules: String) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Muzzle", isDirectory: true)
        .appendingPathComponent("pf-staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let anchorStagingURL = directory.appendingPathComponent("muzzle")
        try Data(rules.utf8).write(to: anchorStagingURL, options: .atomic)
        return anchorStagingURL
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    private func removeLegacyCommand() -> String {
        """
        (/sbin/pfctl -a \(legacyAnchorName) -F all >/dev/null 2>&1 || true) && \\
        /bin/rm -f \(shellQuote(legacyAnchorURL.path))
        """
    }

}
