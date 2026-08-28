import XCTest
@testable import Muzzle

final class DomainValidatorTests: XCTestCase {
    func testNormalizesDomainsAndOptionalScheme() throws {
        XCTAssertEqual(try DomainValidator.normalizedDomain(from: "YouTube.com"), "youtube.com")
        XCTAssertEqual(try DomainValidator.normalizedDomain(from: "https://www.nytimes.com/"), "nytimes.com")
    }

    func testRejectsPathsAddressesAndCredentials() {
        let invalidValues = [
            "youtube.com/watch?v=abc",
            "127.0.0.1",
            "https://name:password@example.com",
            "https://example.com:8443",
            "just words"
        ]

        for value in invalidValues {
            XCTAssertThrowsError(try DomainValidator.normalizedDomain(from: value), value)
        }
    }

    func testPacketFilterRulesBlockResolvedAddresses() {
        let rules = PacketFilterController().rules(
            ipv4Addresses: ["104.21.31.40"],
            ipv6Addresses: ["2606:4700:3033::6815:1f28"]
        )

        XCTAssertTrue(rules.contains("table <muzzle_ipv4> persist { 104.21.31.40 }"))
        XCTAssertTrue(rules.contains("block return out quick inet to <muzzle_ipv4>"))
        XCTAssertTrue(rules.contains("block return out quick inet6 to <muzzle_ipv6>"))
    }

    func testPacketFilterRulesSkipEmptyAddressFamilies() {
        let rules = PacketFilterController().rules(ipv4Addresses: ["104.21.31.40"], ipv6Addresses: [])

        XCTAssertTrue(rules.contains("muzzle_ipv4"))
        XCTAssertFalse(rules.contains("muzzle_ipv6"))
    }

    func testPacketFilterStateTerminationTargetsOnlyBlockedDestinations() {
        let command = PacketFilterController().terminateExistingStatesCommand(
            ipv4Addresses: ["104.21.31.40"],
            ipv6Addresses: ["2606:4700:3033::6815:1f28"]
        )

        XCTAssertTrue(command.contains("pfctl -k 0.0.0.0/0 -k '104.21.31.40'"))
        XCTAssertTrue(command.contains("pfctl -k ::/0 -k '2606:4700:3033::6815:1f28'"))
        XCTAssertFalse(command.contains("-F states"))
        XCTAssertFalse(command.contains("\\n+"))
    }

    func testTimerProgressAdvancesInWholeMinuteSteps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(5 * 60)

        XCTAssertEqual(TimerProgress.minuteStep(startedAt: start, endsAt: end, now: start), 0)
        XCTAssertEqual(TimerProgress.minuteStep(startedAt: start, endsAt: end, now: start.addingTimeInterval(59)), 0)
        XCTAssertEqual(TimerProgress.minuteStep(startedAt: start, endsAt: end, now: start.addingTimeInterval(60)), 0.2)
        XCTAssertEqual(TimerProgress.minuteStep(startedAt: start, endsAt: end, now: start.addingTimeInterval(4 * 60)), 0.8)
        XCTAssertEqual(TimerProgress.minuteStep(startedAt: start, endsAt: end, now: end), 1)
    }
}
