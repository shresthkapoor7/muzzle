import XCTest
@testable import WebsiteBlocker

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

        XCTAssertTrue(rules.contains("table <websiteblocker_ipv4> persist { 104.21.31.40 }"))
        XCTAssertTrue(rules.contains("block return out quick inet to <websiteblocker_ipv4>"))
        XCTAssertTrue(rules.contains("block return out quick inet6 to <websiteblocker_ipv6>"))
    }

    func testPacketFilterRulesSkipEmptyAddressFamilies() {
        let rules = PacketFilterController().rules(ipv4Addresses: ["104.21.31.40"], ipv6Addresses: [])

        XCTAssertTrue(rules.contains("websiteblocker_ipv4"))
        XCTAssertFalse(rules.contains("websiteblocker_ipv6"))
    }
}
