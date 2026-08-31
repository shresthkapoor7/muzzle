import XCTest
@testable import Muzzle

final class DebugModeTests: XCTestCase {
    func testEnablesOnlyForDebugArgument() {
        XCTAssertTrue(DebugMode.isEnabled(arguments: ["Muzzle", "--debug"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle", "--debugging"]))
    }

    @MainActor
    func testDebugBlockerKeepsSessionsInMemory() throws {
        let blocker = BlockerController(isDebugMode: true)
        try blocker.load()

        blocker.add("example.com", allowedBypasses: 0)
        XCTAssertEqual(blocker.blockedDomains, ["example.com"])

        try blocker.endProtection()
        XCTAssertTrue(blocker.blockedDomains.isEmpty)
    }
}
