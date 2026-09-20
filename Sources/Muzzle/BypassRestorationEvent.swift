import Foundation

enum BypassRestorationEvent: String, Encodable {
    case pending
    case restored
    case failed

    var message: String {
        switch self {
        case .pending:
            "The Muzzle bypass has expired. Protection is awaiting macOS administrator approval; websites may still be accessible. Ask the user to approve the prompt."
        case .restored:
            "Muzzle has restored website protection after the bypass."
        case .failed:
            "Muzzle could not restore protection after the bypass. Websites may still be accessible. Ask the user to choose Retry macOS permission and approve the prompt."
        }
    }
}
