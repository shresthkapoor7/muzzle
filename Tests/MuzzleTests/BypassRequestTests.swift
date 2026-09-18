import XCTest
@testable import Muzzle

final class BypassRequestTests: XCTestCase {
    func testRequiresDeliveryAndCannotBeReused() {
        var request = BypassRequest(code: "123456")
        XCTAssertFalse(request.redeem("123456"))
        request.markDelivered()
        XCTAssertTrue(request.redeem(" 123456\n"))
        XCTAssertFalse(request.redeem("123456"))
    }

    func testExpiryAndAttemptLimit() {
        let now = Date()
        var expired = BypassRequest(code: "123456", now: now)
        expired.markDelivered()
        XCTAssertFalse(expired.redeem("123456", now: now.addingTimeInterval(900)))
        var exhausted = BypassRequest(code: "123456")
        exhausted.markDelivered()
        for _ in 0..<5 { XCTAssertFalse(exhausted.redeem("000000")) }
        XCTAssertFalse(exhausted.redeem("123456"))
    }
}
