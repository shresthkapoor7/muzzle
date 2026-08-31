import Foundation

enum DebugMode {
    static var isEnabled: Bool {
        isEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.dropFirst().contains("--debug")
    }
}
