import Foundation

public enum ServicePaths {
    public static let label = "local.muzzle.helper"
    public static let directory = "/Library/Application Support/MuzzleService"
    public static let executable = "/Library/PrivilegedHelperTools/local.muzzle.helper"
    public static let plist = "/Library/LaunchDaemons/local.muzzle.helper.plist"
    public static let socketDirectory = "/var/run/local.muzzle"
    public static let socket = socketDirectory + "/control.sock"
    public static let protocolVersion = 1
}

/// No command accepts shell text, file paths, arbitrary state, or a free allowance grant.
public enum ServiceCommand: Codable, Sendable {
    case status
    case add(domain: String, minutes: Int?, allowance: Int)
    case bypass(minutes: Int)
    case end(code: String)
    case deliverKey(token: String, context: String?)
    case requestExtra(token: String)
    case redeemExtra(code: String)
    case retry
}

public struct ServiceRequest: Codable, Sendable {
    public let version: Int
    public let command: ServiceCommand
    public init(_ command: ServiceCommand) {
        self.version = ServicePaths.protocolVersion
        self.command = command
    }
}

public struct ServiceSnapshot: Codable, Sendable {
    public var sessionID: UUID?
    public var domains: [String] = []
    public var startedAt: Date?
    public var endsAt: Date?
    public var bypassStartedAt: Date?
    public var bypassEndsAt: Date?
    public var remaining = 0
    public var dailyLimit = 0
    public var renewsAt: Date?
    public var isEnforced = false
    public var error: String?
    public init() {}
}

public struct ServiceResponse: Codable, Sendable {
    public let version: Int
    public var snapshot: ServiceSnapshot?
    public var error: String?
    public init(snapshot: ServiceSnapshot? = nil, error: String? = nil) {
        version = ServicePaths.protocolVersion
        self.snapshot = snapshot
        self.error = error
    }
}

public struct ServiceFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ServiceValidation {
    public static func domain(_ value: String) throws -> String {
        let result = value.lowercased()
        let labels = result.split(separator: ".", omittingEmptySubsequences: false)
        guard result.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-"
                  && $0.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) }),
              !labels.allSatisfy({ Int($0) != nil }) else { throw ServiceFailure("Invalid website domain.") }
        return result
    }

    public static func seconds(_ minutes: Int) throws -> TimeInterval {
        guard (1...525600).contains(minutes) else { throw ServiceFailure("Choose between 1 minute and 1 year.") }
        return TimeInterval(minutes) * 60
    }
}
