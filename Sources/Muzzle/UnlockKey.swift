import Foundation
import Security

enum UnlockKey {
    static func make() -> String {
        var randomValue: UInt32 = 0
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            MemoryLayout<UInt32>.size,
            &randomValue
        )
        precondition(status == errSecSuccess, "Could not generate unlock key")
        return String(format: "%06u", randomValue % 1_000_000)
    }
}
