import AppKit
import XCTest
@testable import Muzzle

final class StatusMenuActivationTests: XCTestCase {
    @MainActor
    func testNativeMenuControlClickActivatesOnceAfterTrackingStarts() async {
        let activated = expectation(description: "Activation delivered")
        activated.assertForOverFulfill = true
        let delegate = StatusMenuActivation(isEnabled: { true }, modifiers: { [.control] }) {
            activated.fulfill()
        }
        let menu = NSMenu()
        menu.delegate = delegate
        delegate.menuWillOpen(menu)
        delegate.menuWillOpen(menu)
        await fulfillment(of: [activated], timeout: 1)
    }

    @MainActor
    func testOrdinaryClicksAndDisabledControlClickLeaveMenuAlone() async {
        var activations = 0
        let ordinary = StatusMenuActivation(isEnabled: { true }, modifiers: { [] }) { activations += 1 }
        let disabled = StatusMenuActivation(isEnabled: { false }, modifiers: { [.control] }) { activations += 1 }
        ordinary.menuWillOpen(NSMenu())
        disabled.menuWillOpen(NSMenu())
        await Task.yield()
        XCTAssertEqual(activations, 0)
    }
}
