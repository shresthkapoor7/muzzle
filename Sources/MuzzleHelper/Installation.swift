import Foundation
import Security
import Darwin
import MuzzleService

struct ServiceConfiguration: Codable {
    let ownerUID: UInt32
    let clientRequirement: String
}

enum Installation {
    static let configPath = ServicePaths.directory + "/configuration.json"

    static func install(appPath: String, ownerUID: UInt32) throws {
        guard geteuid() == 0, ownerUID >= 501, let account = getpwuid(ownerUID) else {
            throw ServiceFailure("Install the service as administrator for a normal macOS user.")
        }
        let sourceApp = URL(fileURLWithPath: appPath).standardizedFileURL
        guard sourceApp.pathExtension == "app" else { throw ServiceFailure("Choose a built Muzzle.app bundle.") }
        // Validate a root-owned snapshot, never a bundle the caller can replace
        // between validation and installation. Partial/inconsistent copies fail validation.
        try RootFiles.directory(ServicePaths.directory)
        let staging = URL(fileURLWithPath: ServicePaths.directory).appendingPathComponent("install-" + UUID().uuidString)
        try RootFiles.directory(staging.path)
        defer { try? FileManager.default.removeItem(at: staging) }
        let app = staging.appendingPathComponent("Muzzle.app")
        try FileManager.default.copyItem(at: sourceApp, to: app)
        // Do not let a copied symlink redirect nested-code validation back into
        // caller-writable storage outside the protected staging directory.
        for relative in ["", "Contents", "Contents/Library", "Contents/Library/HelperTools"] {
            try RootFiles.check(app.appendingPathComponent(relative).path, directory: true)
        }
        try RootFiles.check(app.appendingPathComponent("Contents/Library/HelperTools/MuzzleHelper").path)
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate), nil) == errSecSuccess else {
            throw ServiceFailure("The app must have a valid code signature.")
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], values[kSecCodeInfoIdentifier as String] as? String == "local.muzzle.app",
              let hash = values[kSecCodeInfoUnique as String] as? Data else {
            throw ServiceFailure("The selected app is not Muzzle.")
        }
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let flags = (values[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let unsafeEntitlements = ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                                 "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.disable-executable-page-protection"]
        guard flags & SecCodeSignatureFlags.runtime.rawValue != 0,
              !unsafeEntitlements.contains(where: { entitlements[$0] as? Bool == true }) else {
            throw ServiceFailure("Build Muzzle with hardened runtime and without debugging or code-injection entitlements.")
        }
        // Pin this exact build, not just its forgeable bundle identifier. Rebuilt
        // ad-hoc apps require explicit administrator approval to update the pin.
        let config = ServiceConfiguration(ownerUID: ownerUID, clientRequirement: "identifier \"local.muzzle.app\" and cdhash H\"\(hex)\"")
        try RootFiles.directory(ServicePaths.directory)
        if FileManager.default.fileExists(atPath: configPath) {
            try RootFiles.check(configPath)
            let existing = try JSONDecoder().decode(ServiceConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
            guard existing.ownerUID == ownerUID else { throw ServiceFailure("The service belongs to another user. An administrator must uninstall it before changing ownership.") }
        } else {
            let legacy = URL(fileURLWithPath: String(cString: account.pointee.pw_dir))
                .appendingPathComponent("Library/Application Support/Muzzle/blocked-domains.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                let domains = try JSONDecoder().decode([String].self, from: Data(contentsOf: legacy))
                guard domains.isEmpty else { throw ServiceFailure("End the existing session and quit the old Muzzle app before installing the service. Its protection has not been changed.") }
            }
            let hosts = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
            guard !hosts.contains("# MUZZLE_BEGIN"), !hosts.contains("# WEBSITE_BLOCKER_BEGIN"),
                  !FileManager.default.fileExists(atPath: "/etc/pf.anchors/muzzle") else {
                throw ServiceFailure("Existing legacy blocking rules must be ended before installing the service.")
            }
        }
        let source = app.appendingPathComponent("Contents/Library/HelperTools/MuzzleHelper")
        let sourceInfo = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceInfo.isRegularFile == true, sourceInfo.isSymbolicLink != true else { throw ServiceFailure("The packaged helper is missing or invalid.") }
        let helperIdentity = try HelperSignature.identity(of: source)
        let stagedHelper = staging.appendingPathComponent("validated-helper")
        try RootFiles.write(try Data(contentsOf: source), to: stagedHelper.path, mode: 0o700)
        try HelperSignature.validate(stagedHelper, identity: helperIdentity)
        try RootFiles.directory("/Library/PrivilegedHelperTools", mode: 0o755)
        try RootFiles.directory("/Library/LaunchDaemons", mode: 0o755)
        let plist: [String: Any] = ["Label": ServicePaths.label, "ProgramArguments": [ServicePaths.executable],
            "RunAtLoad": true, "KeepAlive": true, "UserName": "root", "Umask": 63,
            "ThrottleInterval": 5, "ProcessType": "Background"]
        // Validate everything before stopping an old helper; saved sessions and
        // installed rules survive the short service update window.
        let binary = try Data(contentsOf: stagedHelper)
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let files: [(String, Data, Int)] = [(ServicePaths.executable, binary, 0o755),
            (configPath, try JSONEncoder().encode(config), 0o600), (ServicePaths.plist, plistData, 0o644)]
        let previous = try files.map { path, _, _ -> Data? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            try RootFiles.check(path)
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        let wasRunning = (try? RootProcess.run("/bin/launchctl", ["print", "system/" + ServicePaths.label])) != nil
        if wasRunning { try RootProcess.run("/bin/launchctl", ["bootout", "system/" + ServicePaths.label]) }
        do {
            for (path, data, mode) in files { try RootFiles.write(data, to: path, mode: mode) }
            try RootProcess.run("/bin/launchctl", ["bootstrap", "system", ServicePaths.plist])
        } catch {
            let installError = error
            do {
                for (index, file) in files.enumerated() {
                    if let data = previous[index] { try RootFiles.write(data, to: file.0, mode: file.2) }
                    else if FileManager.default.fileExists(atPath: file.0) { try FileManager.default.removeItem(atPath: file.0) }
                }
                if wasRunning { try RootProcess.run("/bin/launchctl", ["bootstrap", "system", ServicePaths.plist]) }
            } catch {
                throw ServiceFailure("Service installation and rollback failed. Existing rules and session data were preserved; administrator repair is required.")
            }
            throw installError
        }
    }
}

enum HelperSignature {
    static func identity(of url: URL) throws -> SecRequirement {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw ServiceFailure("The nested helper signature is invalid.")
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data else {
            throw ServiceFailure("Could not capture the nested helper identity.")
        }
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw ServiceFailure("Could not pin the nested helper identity.") }
        return requirement
    }

    static func validate(_ url: URL, identity: SecRequirement) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), identity) == errSecSuccess else {
            throw ServiceFailure("The staged helper does not match the validated nested helper.")
        }
    }
}

enum PeerAuthentication {
    static func validate(fd: Int32, config: ServiceConfiguration) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == config.ownerUID else { return false }
        // The audit token binds identity to this socket peer, avoiding PID reuse.
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              length == MemoryLayout<audit_token_t>.size else { return false }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(config.clientRequirement as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
