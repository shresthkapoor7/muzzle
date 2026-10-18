import AppKit
import XCTest
@testable import Muzzle

final class StatusControlClickTests: XCTestCase {
    @MainActor
    func testInterceptsControlPressBeforeButtonActionForBothMouseEventTypes() throws {
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            let event = try makeEvent(type: type, flags: [.control])
            XCTAssertTrue(StatusControlClickMonitor.shouldHandle(event, windowNumber: 42,
                buttonFrame: NSRect(x: 0, y: 0, width: 24, height: 24), enabled: true))
        }
    }

    @MainActor
    func testLeavesOtherClicksAndWindowsAlone() throws {
        let frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        let control = try makeEvent(type: .leftMouseDown, flags: [.control])
        XCTAssertFalse(StatusControlClickMonitor.shouldHandle(control, windowNumber: 42, buttonFrame: frame, enabled: false))
        XCTAssertFalse(StatusControlClickMonitor.shouldHandle(control, windowNumber: 43, buttonFrame: frame, enabled: true))
        XCTAssertFalse(StatusControlClickMonitor.shouldHandle(control, windowNumber: 42,
            buttonFrame: NSRect(x: 50, y: 50, width: 24, height: 24), enabled: true))
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            let event = try makeEvent(type: type, flags: [])
            XCTAssertFalse(StatusControlClickMonitor.shouldHandle(event, windowNumber: 42, buttonFrame: frame, enabled: true))
        }
        let release = try makeEvent(type: .leftMouseUp, flags: [.control])
        XCTAssertFalse(StatusControlClickMonitor.shouldHandle(release, windowNumber: 42, buttonFrame: frame, enabled: true))
    }

    private func makeEvent(type: NSEvent.EventType, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 12, y: 12),
            modifierFlags: flags, timestamp: 0, windowNumber: 42, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
    }
}
