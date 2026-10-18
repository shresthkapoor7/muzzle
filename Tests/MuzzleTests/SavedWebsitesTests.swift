import XCTest
@testable import Muzzle

final class SavedWebsitesTests: XCTestCase {
    @MainActor func testPersistenceNormalizationAndDebugIsolation() throws {
        let suite = "MuzzleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedWebsites(defaults: defaults, isDebugMode: false)
        try store.add("https://www.Example.com/")
        try store.add("example.com")
        XCTAssertThrowsError(try store.add("invalid"))
        XCTAssertEqual(SavedWebsites(defaults: defaults, isDebugMode: false).domains, ["example.com"])
        XCTAssertTrue(SavedWebsites(defaults: defaults, isDebugMode: true).domains.isEmpty)
        store.remove("example.com")
        XCTAssertTrue(SavedWebsites(defaults: defaults, isDebugMode: false).domains.isEmpty)
    }
}
