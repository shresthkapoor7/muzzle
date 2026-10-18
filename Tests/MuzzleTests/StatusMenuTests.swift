import XCTest
import AppKit
@testable import Muzzle

final class StatusMenuTests: XCTestCase {
    @MainActor func testControlClickRequiresOptInAndControlModifier() {
        XCTAssertFalse(StatusItemController.shouldActivateOnClick(enabled: false, modifiers: [.control]))
        XCTAssertFalse(StatusItemController.shouldActivateOnClick(enabled: true, modifiers: []))
        XCTAssertFalse(StatusItemController.shouldActivateOnClick(enabled: true, modifiers: [.command]))
        XCTAssertTrue(StatusItemController.shouldActivateOnClick(enabled: true, modifiers: [.control]))
    }

    func testServiceStatusAndActiveSessionMenuWithoutWindowServer() {
        let unavailable = StatusMenuPresentation(usesPrivilegedService: true, serviceConnected: false, canQuit: true)
        XCTAssertEqual(unavailable.serviceStatusTitle, "Blocking service: unavailable")
        XCTAssertTrue(unavailable.showsQuit)

        let active = StatusMenuPresentation(usesPrivilegedService: true, serviceConnected: true, canQuit: false)
        XCTAssertEqual(active.serviceStatusTitle, "Blocking service: running")
        XCTAssertFalse(active.showsQuit)

        let inactive = StatusMenuPresentation(usesPrivilegedService: true, serviceConnected: true, canQuit: true)
        XCTAssertTrue(inactive.showsQuit)

        let debug = StatusMenuPresentation(usesPrivilegedService: false, serviceConnected: false, canQuit: false)
        XCTAssertNil(debug.serviceStatusTitle)
        XCTAssertFalse(debug.showsQuit)
    }

    func testUnconfiguredPokePanelCanBeCollapsedAndReopened() {
        var disclosure = PokeKeyDisclosureState()
        XCTAssertTrue(disclosure.isExpanded(isConfigured: false))
        disclosure.setExpanded(false)
        XCTAssertFalse(disclosure.isExpanded(isConfigured: false))
        disclosure.setExpanded(true)
        XCTAssertTrue(disclosure.isExpanded(isConfigured: false))
    }

    func testSavedPokePanelStartsCollapsedAndCanBeOpened() {
        var disclosure = PokeKeyDisclosureState()
        XCTAssertFalse(disclosure.isExpanded(isConfigured: true))
        disclosure.setExpanded(true)
        XCTAssertTrue(disclosure.isExpanded(isConfigured: true))
        disclosure.setExpanded(false)
        XCTAssertFalse(disclosure.isExpanded(isConfigured: true))
    }

    func testSavingCollapsesAndRemovingReopensPokeControls() {
        var disclosure = PokeKeyDisclosureState()
        disclosure.setExpanded(true)
        disclosure.configurationChanged(isConfigured: true)
        XCTAssertFalse(disclosure.isExpanded(isConfigured: true))
        disclosure.configurationChanged(isConfigured: false)
        XCTAssertTrue(disclosure.isExpanded(isConfigured: false))
        disclosure.setExpanded(false)
        XCTAssertFalse(disclosure.isExpanded(isConfigured: false))
    }

    func testHeaderToggleRepeatedlyOpensAndClosesSavedAndUnsavedControls() {
        for configured in [false, true] {
            var disclosure = PokeKeyDisclosureState()
            var expected = !configured
            for _ in 0..<10 {
                disclosure.toggle(isConfigured: configured)
                expected.toggle()
                XCTAssertEqual(disclosure.isExpanded(isConfigured: configured), expected)
            }
        }
    }
}
