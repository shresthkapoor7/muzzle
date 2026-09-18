import XCTest
@testable import Muzzle

final class BypassAllowanceTests: XCTestCase {
    func testRenewsAt24HoursWithoutAccumulatingMissedDays() {
        let now = Date()
        var allowance = BypassAllowance(limit: 2, now: now).consumingOne().consumingOne()
        XCTAssertFalse(allowance.renewIfNeeded(now: now.addingTimeInterval(86399)))
        XCTAssertEqual(allowance.remaining, 0)
        XCTAssertTrue(allowance.renewIfNeeded(now: now.addingTimeInterval(86400)))
        XCTAssertEqual(allowance.remaining, 2)
        allowance = allowance.consumingOne()
        XCTAssertTrue(allowance.renewIfNeeded(now: now.addingTimeInterval(86400 * 5 + 30)))
        XCTAssertEqual(allowance.remaining, 2)
        XCTAssertEqual(allowance.renewsAt, now.addingTimeInterval(86400 * 6))
    }

    func testZeroAllowanceAndExtrasDoNotChangeDailyLimit() throws {
        let now = Date()
        var allowance = BypassAllowance(limit: 0, now: now).grantingOne()
        XCTAssertEqual(allowance.remaining, 1)
        allowance.renewIfNeeded(now: now.addingTimeInterval(86400))
        XCTAssertEqual(allowance.remaining, 0)
        let roundTrip = try JSONDecoder().decode(BypassAllowance.self, from: JSONEncoder().encode(allowance))
        XCTAssertEqual(roundTrip, allowance)
        let legacy = try JSONDecoder().decode(BypassAllowance.self, from: Data(#"{"remaining":0}"#.utf8))
        XCTAssertEqual(legacy.dailyLimit, 0)
    }

    @MainActor
    func testRenewalAndExtraGrantPreservePendingBypassConsumption() async throws {
        let directory = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        defer { try? FileManager.default.removeItem(at: base.appendingPathComponent(directory)) }
        var shouldFail = false
        let blocker = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { _ in
            if shouldFail { throw CocoaError(.userCancelled) }
        })
        try await blocker.load()
        await blocker.add("example.com", allowedBypasses: 2)
        shouldFail = true
        do { try await blocker.startBypass(for: 5); XCTFail("Expected failure") } catch {}
        XCTAssertTrue(blocker.canRetrySystemUpdate)
        try await blocker.renewBypassesIfNeeded(now: try XCTUnwrap(blocker.bypassRenewalDate))
        try blocker.grantExtraBypass()
        XCTAssertEqual(blocker.remainingBypasses, 3)
        XCTAssertThrowsError(try blocker.grantExtraBypass())
        shouldFail = false
        await blocker.retryPendingSystemUpdate()
        XCTAssertTrue(blocker.isBypassActive)
        XCTAssertEqual(blocker.remainingBypasses, 2)
    }

    @MainActor
    func testRenewalKeepsProtectionAndRunningBypassUnchangedAcrossReload() async throws {
        let directory = "MuzzleTests-\(UUID().uuidString)"
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        defer { try? FileManager.default.removeItem(at: base.appendingPathComponent(directory)) }
        var applied: [[String]] = []
        let blocker = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { applied.append($0) })
        try await blocker.load()
        await blocker.add("example.com", allowedBypasses: 2)
        try await blocker.startBypass(for: 5)
        let deadline = blocker.bypassEndDate
        let count = applied.count
        try await blocker.renewBypassesIfNeeded(now: try XCTUnwrap(blocker.bypassRenewalDate))
        XCTAssertEqual(blocker.remainingBypasses, 2)
        XCTAssertEqual(blocker.bypassEndDate, deadline)
        XCTAssertEqual(blocker.blockedDomains, ["example.com"])
        XCTAssertEqual(applied.count, count)
        let reloaded = BlockerController(applicationSupportDirectoryName: directory, applyConfiguration: { _ in XCTFail("Load must not modify system rules") })
        try await reloaded.load()
        XCTAssertEqual(reloaded.remainingBypasses, 2)
        XCTAssertEqual(reloaded.bypassRenewalDate, blocker.bypassRenewalDate)
    }
}
