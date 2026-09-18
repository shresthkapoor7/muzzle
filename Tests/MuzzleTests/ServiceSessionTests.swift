import XCTest
@testable import MuzzleService

final class ServiceSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testBypassRestoresWithoutAnyClientAndSurvivesServiceRestart() throws {
        var saved = ProtectedState()
        var rules: [[String]] = []
        let service = SessionEngine(persist: { saved = $0 }, apply: { rules.append($0) })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 1), now: now)
        try service.handle(.bypass(minutes: 1), now: now)
        XCTAssertEqual(service.snapshot().remaining, 0)
        XCTAssertEqual(rules.last, [])
        let restarted = SessionEngine(state: saved, persist: { saved = $0 }, apply: { rules.append($0) })
        restarted.tick(now: now.addingTimeInterval(61), force: true)
        XCTAssertEqual(rules.last, ["example.com"])
        XCTAssertNil(restarted.snapshot().bypassEndsAt)
        XCTAssertTrue(restarted.snapshot().isEnforced)
    }

    func testDeadlineStillEnforcesWhenPersistenceFails() throws {
        var failPersistence = false
        var rules: [[String]] = []
        let service = SessionEngine(persist: { _ in if failPersistence { throw CocoaError(.fileWriteNoPermission) } },
                                    apply: { rules.append($0) })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 1), now: now)
        try service.handle(.bypass(minutes: 1), now: now)
        failPersistence = true
        service.tick(now: now.addingTimeInterval(61))
        XCTAssertEqual(rules.last, ["example.com"])
        XCTAssertNotNil(service.snapshot().error)
        failPersistence = false
        service.tick(now: now.addingTimeInterval(62))
        XCTAssertNil(service.snapshot().bypassEndsAt)
        XCTAssertNil(service.snapshot().error)
    }

    func testRuleFailureRetriesAutomatically() throws {
        var shouldFail = false
        var count = 0
        let service = SessionEngine(persist: { _ in }, apply: { _ in
            count += 1
            if shouldFail { throw CocoaError(.fileWriteUnknown) }
        })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 1), now: now)
        try service.handle(.bypass(minutes: 1), now: now)
        shouldFail = true
        service.tick(now: now.addingTimeInterval(61))
        XCTAssertNotNil(service.snapshot().error)
        let failedCount = count
        shouldFail = false
        service.tick(now: now.addingTimeInterval(62))
        XCTAssertGreaterThan(count, failedCount)
        XCTAssertTrue(service.snapshot().isEnforced)
        XCTAssertNil(service.snapshot().error)
    }

    func testDailyRenewalDoesNotEndProtectionOrAccumulateMissedDays() throws {
        let service = SessionEngine(persist: { _ in }, apply: { _ in })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 2), now: now)
        try service.handle(.bypass(minutes: 1), now: now)
        service.tick(now: now.addingTimeInterval(5 * 86400))
        XCTAssertEqual(service.snapshot().remaining, 2)
        XCTAssertEqual(service.snapshot().renewsAt, now.addingTimeInterval(6 * 86400))
        XCTAssertTrue(service.snapshot().isEnforced)
    }

    func testTimedSessionCannotBeEndedEarlyAndExpiresWithoutApp() throws {
        var rules: [[String]] = []
        let service = SessionEngine(persist: { _ in }, apply: { rules.append($0) }, makeCode: { "123456" })
        try service.handle(.add(domain: "example.com", minutes: 2, allowance: 1), now: now)
        XCTAssertThrowsError(try service.handle(.end(code: "123456"), now: now))
        try service.handle(.bypass(minutes: 5), now: now)
        XCTAssertEqual(service.snapshot().bypassEndsAt, now.addingTimeInterval(120))
        service.tick(now: now.addingTimeInterval(120))
        XCTAssertTrue(service.snapshot().domains.isEmpty)
        XCTAssertEqual(rules.last, [])
    }

    func testUnlockRateLimitSurvivesRestartAndSecretsNeverReachSnapshot() throws {
        var saved = ProtectedState()
        let service = SessionEngine(persist: { saved = $0 }, apply: { _ in }, makeCode: { "123456" })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 0), now: now)
        let delivery = try XCTUnwrap(service.handle(.deliverKey(token: "private-token", context: nil), now: now))
        XCTAssertEqual(delivery.payload["key"], "123456")
        let response = String(decoding: try JSONEncoder().encode(ServiceResponse(snapshot: service.snapshot())), as: UTF8.self)
        XCTAssertFalse(response.contains("123456"))
        XCTAssertFalse(response.contains("private-token"))
        for _ in 0..<5 { XCTAssertThrowsError(try service.handle(.end(code: "000000"), now: now)) }
        let restarted = SessionEngine(state: saved, persist: { saved = $0 }, apply: { _ in })
        XCTAssertThrowsError(try restarted.handle(.end(code: "123456"), now: now))
        try restarted.handle(.end(code: "123456"), now: now.addingTimeInterval(901))
        XCTAssertTrue(restarted.snapshot().domains.isEmpty)
    }

    func testExtraApprovalRequiresDeliveryAndGrantIsAtomic() throws {
        var shouldFail = false
        let service = SessionEngine(persist: { _ in if shouldFail { throw CocoaError(.fileWriteNoPermission) } },
                                    apply: { _ in }, makeCode: { "234567" })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 0), now: now)
        let delivery = try XCTUnwrap(service.handle(.requestExtra(token: "test-token"), now: now))
        XCTAssertThrowsError(try service.handle(.redeemExtra(code: "234567"), now: now))
        try service.confirmDelivery(delivery, now: now)
        shouldFail = true
        XCTAssertThrowsError(try service.handle(.redeemExtra(code: "234567"), now: now))
        XCTAssertEqual(service.snapshot().remaining, 0)
        shouldFail = false
        try service.handle(.redeemExtra(code: "234567"), now: now)
        XCTAssertEqual(service.snapshot().remaining, 1)
        XCTAssertThrowsError(try service.handle(.redeemExtra(code: "234567"), now: now))
    }

    func testFailedBypassPersistenceDoesNotRemoveRulesOrSpendAllowance() throws {
        var shouldFail = false
        var rules: [[String]] = []
        let service = SessionEngine(persist: { _ in if shouldFail { throw CocoaError(.fileWriteNoPermission) } },
                                    apply: { rules.append($0) })
        try service.handle(.add(domain: "example.com", minutes: nil, allowance: 1), now: now)
        let count = rules.count
        shouldFail = true
        XCTAssertThrowsError(try service.handle(.bypass(minutes: 1), now: now))
        XCTAssertEqual(service.snapshot().remaining, 1)
        XCTAssertNil(service.snapshot().bypassEndsAt)
        XCTAssertEqual(rules.count, count)
    }

    func testInvalidRequestsCannotIntroduceShellCommandsOrArbitraryPaths() throws {
        let service = SessionEngine(persist: { _ in }, apply: { _ in })
        for domain in ["example.com;id", "$(id).com", "/etc/hosts", "example.com\npass out", "127.0.0.1"] {
            XCTAssertThrowsError(try service.handle(.add(domain: domain, minutes: nil, allowance: 1), now: now))
        }
        XCTAssertTrue(service.snapshot().domains.isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(ServiceRequest.self, from: Data(#"{"version":1,"command":{"shell":{"command":"id"}}}"#.utf8)))
        XCTAssertThrowsError(try ServiceValidation.seconds(Int.max))
    }
}
