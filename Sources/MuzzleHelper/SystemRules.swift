import Foundation
import Darwin
import MuzzleService

final class SystemRules {
    private struct Addresses: Codable { var ipv4: [String]; var ipv6: [String] }
    private var cache: [String: Addresses] = [:]
    private let cachePath = ServicePaths.directory + "/addresses.json"
    private let anchor = "com.apple/muzzle"
    private let anchorPath = "/etc/pf.anchors/muzzle"
    private let opening = "# MUZZLE_BEGIN — managed by Muzzle"
    private let closing = "# MUZZLE_END"

    init() throws {
        if FileManager.default.fileExists(atPath: cachePath) {
            try RootFiles.check(cachePath)
            cache = try JSONDecoder().decode([String: Addresses].self, from: Data(contentsOf: URL(fileURLWithPath: cachePath)))
        }
    }

    func apply(_ rawDomains: [String]) throws {
        let domains = try rawDomains.map(ServiceValidation.domain)
        // Install the hosts layer first: a DNS/PF failure must not leave an
        // expired bypass with both layers absent.
        let old = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
        var hosts = old
        while let start = hosts.range(of: opening) {
            guard let end = hosts.range(of: closing, range: start.upperBound..<hosts.endIndex) else {
                throw ServiceFailure("Muzzle's hosts-file section is incomplete; administrator repair is required.")
            }
            hosts.removeSubrange(start.lowerBound..<end.upperBound)
        }
        if !domains.isEmpty {
            if !hosts.hasSuffix("\n") { hosts += "\n" }
            hosts += "\n\(opening)\n"
            hosts += domains.flatMap { ["127.0.0.1 \($0)", "127.0.0.1 www.\($0)", "::1 \($0)", "::1 www.\($0)"] }.joined(separator: "\n")
            hosts += "\n\(closing)\n"
        }
        if hosts != old {
            try RootFiles.write(Data(hosts.utf8), to: "/private/etc/hosts", mode: 0o644)
            try RootProcess.run("/usr/bin/dscacheutil", ["-flushcache"])
            _ = try? RootProcess.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        }
        guard !domains.isEmpty else {
            try RootProcess.run("/sbin/pfctl", ["-a", anchor, "-F", "all"])
            if FileManager.default.fileExists(atPath: anchorPath) {
                try RootFiles.check(anchorPath)
                try FileManager.default.removeItem(atPath: anchorPath)
            }
            return
        }

        // Reuse root-owned resolved addresses at bypass expiry and after restart;
        // network availability must not be required to restore an existing block.
        for domain in domains where cache[domain] == nil {
            let v4 = try resolve(domain, record: "A", family: AF_INET)
            let v6 = try resolve(domain, record: "AAAA", family: AF_INET6)
            guard !v4.isEmpty || !v6.isEmpty else { throw ServiceFailure("Could not resolve \(domain); hosts blocking is active and the service will retry the firewall.") }
            cache[domain] = Addresses(ipv4: v4, ipv6: v6)
            try RootFiles.write(try JSONEncoder().encode(cache), to: cachePath)
        }
        let v4 = Array(Set(domains.flatMap { cache[$0]?.ipv4 ?? [] })).sorted()
        let v6 = Array(Set(domains.flatMap { cache[$0]?.ipv6 ?? [] })).sorted()
        var rules = "# Managed by Muzzle's privileged service\n"
        if !v4.isEmpty { rules += "table <muzzle_ipv4> persist { \(v4.joined(separator: ", ")) }\nblock return out quick inet to <muzzle_ipv4>\n" }
        if !v6.isEmpty { rules += "table <muzzle_ipv6> persist { \(v6.joined(separator: ", ")) }\nblock return out quick inet6 to <muzzle_ipv6>\n" }
        try RootFiles.write(Data(rules.utf8), to: anchorPath)
        try RootProcess.run("/sbin/pfctl", ["-a", anchor, "-f", anchorPath])
        _ = try? RootProcess.run("/sbin/pfctl", ["-e"])
        let status = try RootProcess.run("/sbin/pfctl", ["-s", "info"])
        guard String(decoding: status, as: UTF8.self).contains("Status: Enabled") else {
            throw ServiceFailure("The packet filter is not enabled; hosts blocking remains active and the service will retry.")
        }
        for address in v4 { _ = try? RootProcess.run("/sbin/pfctl", ["-k", "0.0.0.0/0", "-k", address]) }
        for address in v6 { _ = try? RootProcess.run("/sbin/pfctl", ["-k", "::/0", "-k", address]) }
    }

    private func resolve(_ domain: String, record: String, family: Int32) throws -> [String] {
        let output = try RootProcess.run("/usr/bin/dig", ["+short", "+time=1", "+tries=1", record, domain, "www." + domain], timeout: 3)
        return String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { value in
            var bytes = [UInt8](repeating: 0, count: 16)
            return inet_pton(family, value, &bytes) == 1 && value != "127.0.0.1" && value != "::1"
        }
    }
}
