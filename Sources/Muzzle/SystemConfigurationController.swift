import Foundation

/// Applies the packet-filter and hosts-file changes through one macOS authorization request.
struct SystemConfigurationController {
    private let fileManager = FileManager.default
    private let hostsFileController = HostsFileController()
    private let packetFilterController = PacketFilterController()

    enum SystemConfigurationError: LocalizedError {
        case privilegeCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .privilegeCommandFailed(let details):
                "macOS did not update website blocking. \(details)"
            }
        }
    }

    func apply(_ domains: [String]) throws {
        let hostsStagingURL = try hostsFileController.makeStagingFile(for: domains)
        defer { try? fileManager.removeItem(at: hostsStagingURL) }

        let packetFilterCommand: String
        var packetFilterStagingDirectory: URL?
        if domains.isEmpty {
            packetFilterCommand = packetFilterController.removeCommand()
        } else {
            let anchorStagingURL = try packetFilterController.makeStagingAnchor(for: domains)
            packetFilterStagingDirectory = anchorStagingURL.deletingLastPathComponent()
            packetFilterCommand = packetFilterController.installCommand(anchor: anchorStagingURL)
        }
        defer {
            if let packetFilterStagingDirectory {
                try? fileManager.removeItem(at: packetFilterStagingDirectory)
            }
        }

        let command = """
        \(packetFilterCommand) && \\
        \(hostsFileController.installCommand(from: hostsStagingURL))
        """
        try runWithAdministratorPrivileges(command)
    }

    private func runWithAdministratorPrivileges(_ command: String) throws {
        let source = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let details = error[NSAppleScript.errorMessage] as? String ?? "Administrator access was cancelled or denied."
            throw SystemConfigurationError.privilegeCommandFailed(details)
        }
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
