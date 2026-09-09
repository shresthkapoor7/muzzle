import XCTest
@testable import Muzzle

final class UpdateCheckerTests: XCTestCase {
    func testVersionsCompareNumericallyAndNormalizeMissingPatch() throws {
        XCTAssertEqual(AppVersion("v1.0.0"), AppVersion("1.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.0")), try XCTUnwrap(AppVersion("1.10.0")))
        for invalid in ["", "1", "1.0-beta", "1..2", "1.2.3.4", "one.two", "-1.2"] {
            XCTAssertNil(AppVersion(invalid))
        }
    }

    func testSelectsMatchingArchitectureAndRejectsDowngrades() throws {
        let release = try fixture()
        let update = try XCTUnwrap(release.update(currentVersion: "1.0", architecture: "arm64"))
        XCTAssertTrue(update.downloadURL.lastPathComponent.hasSuffix("arm64.dmg"))
        XCTAssertTrue(try XCTUnwrap(release.update(currentVersion: "1.0", architecture: "x86_64"))
            .downloadURL.lastPathComponent.hasSuffix("x86_64.dmg"))
        XCTAssertNil(try release.update(currentVersion: "1.2.3", architecture: "arm64"))
        XCTAssertNil(try release.update(currentVersion: "2.0.0", architecture: "arm64"))
        XCTAssertThrowsError(try release.update(currentVersion: "", architecture: "arm64"))
        XCTAssertThrowsError(try release.update(currentVersion: "1.0", architecture: "unsupported"))
    }

    func testSkipsPrereleasesAndRejectsUntrustedDownload() throws {
        XCTAssertNil(try fixture(prerelease: true).update(currentVersion: "1.0", architecture: "arm64"))
        XCTAssertThrowsError(try fixture(host: "example.com").update(currentVersion: "1.0", architecture: "arm64"))
    }

    func testNoReleaseRateLimitAndMalformedResponses() throws {
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: UpdateChecker.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
        XCTAssertNil(try UpdateChecker.decodeResponse(data: Data(), response: response(404), currentVersion: "1.0"))
        for status in [403, 429, 500] {
            XCTAssertThrowsError(try UpdateChecker.decodeResponse(data: Data(), response: response(status), currentVersion: "1.0"))
        }
        XCTAssertThrowsError(try UpdateChecker.decodeResponse(data: Data("not json".utf8), response: response(200), currentVersion: "1.0"))
    }

    private func fixture(prerelease: Bool = false, host: String = "github.com") throws -> GitHubRelease {
        let payload: [String: Any] = [
            "tag_name": "v1.2.3", "draft": false, "prerelease": prerelease,
            "html_url": "https://github.com/shresthkapoor7/muzzle/releases/tag/v1.2.3",
            "assets": ["arm64", "x86_64"].map { architecture in
                ["name": "Muzzle-v1.2.3-\(architecture).dmg",
                 "browser_download_url": "https://\(host)/shresthkapoor7/muzzle/releases/download/v1.2.3/Muzzle-v1.2.3-\(architecture).dmg"]
            }
        ]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
