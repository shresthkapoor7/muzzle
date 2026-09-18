import Foundation

/// A grant is valid only in this process, after delivery, and for one redemption.
struct BypassRequest {
    let code: String
    let expiresAt: Date
    private(set) var isDelivered = false
    private(set) var attemptsRemaining = 5

    init(code: String = UnlockKey.make(), now: Date = Date()) {
        self.code = code
        expiresAt = now.addingTimeInterval(15 * 60)
    }

    mutating func markDelivered() { isDelivered = true }

    mutating func redeem(_ input: String, now: Date = Date()) -> Bool {
        guard isDelivered, now < expiresAt, attemptsRemaining > 0 else { return false }
        attemptsRemaining -= 1
        guard input.trimmingCharacters(in: .whitespacesAndNewlines) == code else { return false }
        attemptsRemaining = 0
        return true
    }
}
