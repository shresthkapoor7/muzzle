import XCTest
import MuzzleService
@testable import Muzzle

final class ServiceClientTests: XCTestCase {
    @MainActor
    func testFailedPollPreservesLastKnownEnforcement() async {
        let blocker = BlockerController(serviceRequest: { _ in throw ServiceFailure("offline") })
        var snapshot = ServiceSnapshot()
        snapshot.domains = ["example.com"]
        snapshot.isEnforced = true
        blocker.acceptServiceResponse(ServiceResponse(snapshot: snapshot))
        await blocker.pollServiceStatus()
        XCTAssertFalse(blocker.serviceConnected)
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertEqual(blocker.blockedDomains, ["example.com"])
        XCTAssertTrue(blocker.statusMessage.contains("unavailable"))
    }

    @MainActor
    func testCommandsLeaveMainActorResponsiveAndApplyResponsesInOrder() async throws {
        let started = expectation(description: "First request started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let blocker = BlockerController(serviceRequest: { command in
            XCTAssertFalse(Thread.isMainThread)
            var snapshot = ServiceSnapshot()
            switch command {
            case .add:
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { throw ServiceFailure("Test timed out") }
                snapshot.domains = ["first.example"]
                return ServiceResponse(snapshot: snapshot, error: "Rule update failed")
            case .retry:
                snapshot.domains = ["second.example"]
                return ServiceResponse(snapshot: snapshot)
            default: throw ServiceFailure("Unexpected command")
            }
        })
        let first = Task { try await blocker.serviceCommand(.add(domain: "first.example", minutes: nil, allowance: 1)) }
        let waitResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(waitResult, .completed)
        // This runs on MainActor while the first socket request is blocked.
        XCTAssertTrue(blocker.isApplying)
        let second = Task { try await blocker.serviceCommand(.retry) }
        await Task.yield()
        XCTAssertTrue(blocker.blockedDomains.isEmpty)
        release.signal()
        do { try await first.value; XCTFail("Expected first request error") }
        catch { XCTAssertEqual(error.localizedDescription, "Rule update failed") }
        try await second.value
        XCTAssertEqual(blocker.blockedDomains, ["second.example"])
        XCTAssertFalse(blocker.isApplying)
        XCTAssertNil(blocker.lastErrorMessage)
    }

    @MainActor
    func testFailedCommandStillAppliesAuthoritativeSnapshot() async {
        let blocker = BlockerController(serviceRequest: { _ in
            var snapshot = ServiceSnapshot()
            snapshot.domains = ["example.com"]
            return ServiceResponse(snapshot: snapshot, error: "Partial failure")
        })
        do { try await blocker.serviceCommand(.retry); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Partial failure") }
        XCTAssertEqual(blocker.blockedDomains, ["example.com"])
        XCTAssertFalse(blocker.isApplying)
    }

    @MainActor
    func testStalePollFailureCannotOverwriteNewCommandResponse() async throws {
        let started = expectation(description: "Poll started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let blocker = BlockerController(serviceRequest: { command in
            if case .status = command {
                started.fulfill()
                _ = release.wait(timeout: .now() + 5)
                throw ServiceFailure("Old poll failed")
            }
            var snapshot = ServiceSnapshot()
            snapshot.domains = ["example.com"]
            snapshot.isEnforced = true
            return ServiceResponse(snapshot: snapshot)
        })
        let poll = Task { await blocker.pollServiceStatus() }
        let waitResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(waitResult, .completed)
        try await blocker.serviceCommand(.retry)
        release.signal()
        await poll.value
        XCTAssertTrue(blocker.serviceConnected)
        XCTAssertTrue(blocker.isProtectionEnforced)
        XCTAssertFalse(blocker.statusMessage.contains("unavailable"))
    }
}
