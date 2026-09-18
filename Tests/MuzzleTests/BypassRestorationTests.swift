import XCTest
import CoreFoundation
@testable import Muzzle

final class BypassRestorationTests: XCTestCase {
    @MainActor
    func testBypassDeadlineFiresWhileTrackingMenu() throws {
        let fixture = try makeBypassFixture(endsAt: Date().addingTimeInterval(0.1))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var applied: [[String]] = []
        let blocker = BlockerController(applicationSupportDirectoryName: fixture.directory.lastPathComponent,
                                        applyConfiguration: { applied.append($0) })
        try blocker.load()
        // Simulate an AppKit menu/modal mode rather than the default run loop.
        let mode = CFRunLoopMode(rawValue: "MuzzleTestTracking" as CFString)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), mode)
        CFRunLoopRunInMode(mode, 0.4, false)
        XCTAssertEqual(applied, [["example.com"]])
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertNil(try fixture.store.load())
    }

    @MainActor
    func testDeadlineDuringSystemUpdateIsDeferredInsteadOfDropped() throws {
        let fixture = try makeBypassFixture(endsAt: Date().addingTimeInterval(0.1))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let mode = CFRunLoopMode(rawValue: "MuzzleTestTracking" as CFString)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), mode)
        var applied: [[String]] = []
        let blocker = BlockerController(applicationSupportDirectoryName: fixture.directory.lastPathComponent,
                                        applyConfiguration: { domains in
            applied.append(domains)
            if domains.isEmpty {
                // Simulate an administrator dialog processing events past the deadline.
                CFRunLoopRunInMode(mode, 0.3, false)
                XCTAssertEqual(applied, [[]], "Do not start a nested privileged operation")
            }
        })
        try blocker.load()
        try blocker.reconcileSystemState()
        CFRunLoopRunInMode(mode, 1.5, false)
        XCTAssertEqual(applied, [[], ["example.com"]])
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertNil(try fixture.store.load())
    }

    @MainActor
    func testFailedAutomaticRestorationOffersRetryWithoutRepeatedPrompts() async throws {
        let fixture = try makeBypassFixture(endsAt: Date().addingTimeInterval(0.05))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var attempts = 0
        let blocker = BlockerController(applicationSupportDirectoryName: fixture.directory.lastPathComponent,
                                        applyConfiguration: { _ in
            attempts += 1
            throw CocoaError(.userCancelled)
        })
        try blocker.load()
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(blocker.canRetrySystemUpdate)
        XCTAssertNotNil(blocker.lastErrorMessage)
        XCTAssertNotNil(try fixture.store.load())
    }

    private func makeBypassFixture(endsAt: Date) throws -> (directory: URL, store: BypassSessionStore) {
        let name = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent(name)
        try DomainStore(applicationSupportDirectoryName: name, migratesLegacyStore: false).save(["example.com"])
        let store = BypassSessionStore(applicationSupportDirectoryName: name)
        try store.save(startedAt: Date().addingTimeInterval(-60), endsAt: endsAt)
        return (directory, store)
    }

    @MainActor
    func testAlreadyExpiredBypassTriggersRestorationWithoutManualReconcile() async throws {
        let directory = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        defer { try? FileManager.default.removeItem(at: base.appendingPathComponent(directory)) }
        try DomainStore(applicationSupportDirectoryName: directory, migratesLegacyStore: false).save(["example.com"])
        let bypassStore = BypassSessionStore(applicationSupportDirectoryName: directory)
        try bypassStore.save(startedAt: Date().addingTimeInterval(-120), endsAt: Date().addingTimeInterval(-60))
        var applied: [[String]] = []
        let blocker = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { applied.append($0) })
        try blocker.load()
        let timeout = Date().addingTimeInterval(2)
        while blocker.isBypassActive && Date() < timeout {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(applied, [["example.com"]])
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertNil(try bypassStore.load())
    }

    @MainActor
    func testFailedAddPersistencePreservesPendingRestoration() throws {
        let directory = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let sessionDirectory = base.appendingPathComponent(directory)
        defer { try? FileManager.default.removeItem(at: sessionDirectory) }
        let domainStore = DomainStore(applicationSupportDirectoryName: directory, migratesLegacyStore: false)
        try domainStore.save(["example.com"])
        let bypassStore = BypassSessionStore(applicationSupportDirectoryName: directory)
        try bypassStore.save(startedAt: Date().addingTimeInterval(-120), endsAt: Date().addingTimeInterval(-60))
        var shouldFail = true
        var appliedDomains: [[String]] = []
        let blocker = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { domains in
            appliedDomains.append(domains)
            if shouldFail { throw CocoaError(.userCancelled) }
        })
        try blocker.load()
        XCTAssertThrowsError(try blocker.reconcileSystemState())
        XCTAssertTrue(blocker.canRetrySystemUpdate)

        // Make persistence fail without touching real application data or system rules.
        let domainsURL = sessionDirectory.appendingPathComponent("blocked-domains.json")
        let backupURL = sessionDirectory.appendingPathComponent("blocked-domains.backup")
        try FileManager.default.moveItem(at: domainsURL, to: backupURL)
        try FileManager.default.createDirectory(at: domainsURL, withIntermediateDirectories: false)
        blocker.add("example.org")
        XCTAssertNotNil(blocker.lastErrorMessage)
        XCTAssertEqual(blocker.blockedDomains, ["example.com"])
        XCTAssertEqual(appliedDomains, [["example.com"]])
        XCTAssertTrue(blocker.canRetrySystemUpdate)
        try FileManager.default.removeItem(at: domainsURL)
        try FileManager.default.moveItem(at: backupURL, to: domainsURL)

        shouldFail = false
        blocker.retryPendingSystemUpdate()
        XCTAssertEqual(appliedDomains, [["example.com"], ["example.com"]])
        XCTAssertEqual(try domainStore.load(), ["example.com"])
        XCTAssertNil(try bypassStore.load())
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertFalse(blocker.canRetrySystemUpdate)
    }

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
