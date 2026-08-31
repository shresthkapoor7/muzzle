import XCTest
@testable import Muzzle

final class DebugModeTests: XCTestCase {
    func testEnablesOnlyForDebugArgument() {
        XCTAssertTrue(DebugMode.isEnabled(arguments: ["Muzzle", "--debug"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle", "--debugging"]))
    }
}
