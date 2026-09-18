import XCTest
import Darwin
import Security
@testable import MuzzleHelper

/// Run only in Actions with sudo; every write is confined to disposable fixtures.
final class StagingTests: XCTestCase {
    func testCopiedUserOwnedBundleIsSecuredBeforeValidation() throws {
        guard geteuid() == 0 else { throw XCTSkip("Run the privileged staging step in GitHub Actions") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muzzle-staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Muzzle.app")
        let helper = app.appendingPathComponent("helper")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: helper)
        let identity = try HelperSignature.identity(of: helper)
        XCTAssertEqual(chown(app.path, 501, 20), 0)
        XCTAssertEqual(chmod(app.path, 0o777), 0)
        XCTAssertEqual(chown(helper.path, 501, 20), 0)
        XCTAssertEqual(chmod(helper.path, 0o777), 0)
        XCTAssertThrowsError(try RootFiles.check(app.path, directory: true))

        try RootFiles.secureStagedTree(app.path)
        XCTAssertNoThrow(try RootFiles.check(app.path, directory: true))
        XCTAssertNoThrow(try RootFiles.check(helper.path))
        XCTAssertNoThrow(try HelperSignature.validate(helper, identity: identity))
    }

    func testStagingRejectsSymlinkWithoutChangingTarget() throws {
        guard geteuid() == 0 else { throw XCTSkip("Run the privileged staging step in GitHub Actions") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muzzle-staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("outside")
        try Data("unchanged".utf8).write(to: target)
        XCTAssertEqual(chown(target.path, 501, 20), 0)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try RootFiles.secureStagedTree(link.path))
        var info = stat()
        XCTAssertEqual(lstat(target.path, &info), 0)
        XCTAssertEqual(info.st_uid, 501)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "unchanged")
    }

    func testPackagedAppRemainsValidAfterSecuringSnapshot() throws {
        guard geteuid() == 0, let source = ProcessInfo.processInfo.environment["MUZZLE_TEST_APP"] else {
            throw XCTSkip("Requires the packaged-app staging step in GitHub Actions")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muzzle-staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Muzzle.app")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: app)
        try RootFiles.secureStagedTree(app.path)
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(app as CFURL, [], &code), errSecSuccess)
        let validCode = try XCTUnwrap(code)
        XCTAssertEqual(SecStaticCodeCheckValidity(validCode,
            SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate), nil), errSecSuccess)
        let helper = app.appendingPathComponent("Contents/Library/HelperTools/MuzzleHelper")
        let identity = try HelperSignature.identity(of: helper)
        let staged = directory.appendingPathComponent("validated-helper")
        try RootFiles.write(try Data(contentsOf: helper), to: staged.path, mode: 0o700)
        XCTAssertNoThrow(try HelperSignature.validate(staged, identity: identity))
    }
}
