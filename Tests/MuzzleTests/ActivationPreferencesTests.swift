import XCTest
@testable import Muzzle

final class ActivationPreferencesTests: XCTestCase {
    func testSessionValidation() {
        var session = ActivationSession()
        XCTAssertTrue(session.isValid)
        for input in ["0", "-1", "abc", "1.5", "999999999999999999999999"] {
            session.minutes = input
            XCTAssertFalse(session.isValid)
        }
        session.timed = false
        XCTAssertTrue(session.isValid)
        session.bypasses = 4
        XCTAssertFalse(session.isValid)
    }

    @MainActor func testLocalPersistenceAndDebugIsolation() throws {
        let suite = "MuzzleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ActivationPreferences(defaults: defaults, isDebugMode: false)
        preferences.settings.keyboardSession.timed = false
        preferences.settings.keyboardSession.minutes = "45"
        let reloaded = ActivationPreferences(defaults: defaults, isDebugMode: false)
        XCTAssertFalse(reloaded.settings.keyboardSession.timed)
        XCTAssertEqual(reloaded.settings.keyboardSession.minutes, "45")
        XCTAssertTrue(ActivationPreferences(defaults: defaults, isDebugMode: true).settings.keyboardSession.timed)
    }
}
