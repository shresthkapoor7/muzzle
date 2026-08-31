import Foundation

enum DebugMode {
    static var isEnabled: Bool {
        isEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.dropFirst().contains("--debug")
    }
}

enum BlockingProfile {
    case normal
    case debug

    var applicationSupportDirectoryName: String {
        self == .debug ? "Muzzle Debug" : "Muzzle"
    }

    var hostsOpeningMarker: String {
        self == .debug
            ? "# MUZZLE_DEBUG_BEGIN — managed by Muzzle Debug"
            : "# MUZZLE_BEGIN — managed by Muzzle"
    }

    var hostsClosingMarker: String {
        self == .debug ? "# MUZZLE_DEBUG_END" : "# MUZZLE_END"
    }

    var packetFilterAnchorFileName: String {
        self == .debug ? "muzzle-debug" : "muzzle"
    }

    var packetFilterAnchorName: String {
        self == .debug ? "com.apple/muzzle-debug" : "com.apple/muzzle"
    }
}
