import XCTest
@testable import Muzzle

final class BypassRestorationTests: XCTestCase {
    @MainActor
    func testExpiredBypassNotifiesBeforeAuthorizationAndSurvivesFailure() throws {
        let directory = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        defer { try? FileManager.default.removeItem(at: base.appendingPathComponent(directory)) }
        try DomainStore(applicationSupportDirectoryName: directory, migratesLegacyStore: false).save(["example.com"])
        let bypassStore = BypassSessionStore(applicationSupportDirectoryName: directory)
        try bypassStore.save(startedAt: Date().addingTimeInterval(-120), endsAt: Date().addingTimeInterval(-60))
        var events: [BypassRestorationEvent] = []
        var shouldFail = true
        var expectedDomains = ["example.com"]
        let blocker = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { domains in
            XCTAssertEqual(events.last, .pending)
            XCTAssertEqual(domains, expectedDomains)
            if shouldFail { throw CocoaError(.userCancelled) }
        })
        blocker.onBypassRestoration = { events.append($0) }
        try blocker.load()
        XCTAssertTrue(blocker.isBypassActive)
        XCTAssertThrowsError(try blocker.reconcileSystemState())
        XCTAssertEqual(events, [.pending, .failed])
        XCTAssertNotNil(try bypassStore.load())
        XCTAssertTrue(blocker.canRetrySystemUpdate)
        // Adding another site must not discard the overdue restoration retry.
        expectedDomains = ["example.com", "example.org"]
        blocker.add("example.org")
        XCTAssertTrue(blocker.canRetrySystemUpdate)
        XCTAssertEqual(events, [.pending, .failed, .pending, .failed])
        shouldFail = false
        blocker.retryPendingSystemUpdate()
        XCTAssertEqual(events, [.pending, .failed, .pending, .failed, .pending, .restored])
        XCTAssertNil(try bypassStore.load())
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertFalse(blocker.canRetrySystemUpdate)
    }
}
