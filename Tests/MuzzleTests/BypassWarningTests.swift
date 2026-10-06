import XCTest
@testable import Muzzle

final class BypassWarningTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testWarnsOnceAtTwoMinutesAndAgainForNextBypass() {
        var state = BypassWarningState()
        let end = start.addingTimeInterval(300)
        XCTAssertFalse(state.shouldWarn(start: start, end: end, now: end.addingTimeInterval(-121)))
        XCTAssertTrue(state.shouldWarn(start: start, end: end, now: end.addingTimeInterval(-120)))
        XCTAssertFalse(state.shouldWarn(start: start, end: end, now: end.addingTimeInterval(-119)))
        let nextEnd = end.addingTimeInterval(600)
        XCTAssertTrue(state.shouldWarn(start: end, end: nextEnd, now: nextEnd.addingTimeInterval(-120)))
    }

    func testLateWakeWarnsOnlyWhileBypassStillActive() {
        var state = BypassWarningState()
        let end = start.addingTimeInterval(300)
        XCTAssertTrue(state.shouldWarn(start: start, end: end, now: end.addingTimeInterval(-30)))
        var expired = BypassWarningState()
        XCTAssertFalse(expired.shouldWarn(start: start, end: end, now: end))
        XCTAssertFalse(expired.shouldWarn(start: start, end: end, now: end.addingTimeInterval(1)))
    }

    func testShortAndInactiveBypassesDoNotWarn() {
        var state = BypassWarningState()
        XCTAssertFalse(state.shouldWarn(start: start, end: start.addingTimeInterval(120), now: start))
        XCTAssertFalse(state.shouldWarn(start: start, end: start.addingTimeInterval(60), now: start))
        XCTAssertFalse(state.shouldWarn(start: nil, end: nil, now: start))
    }
}
