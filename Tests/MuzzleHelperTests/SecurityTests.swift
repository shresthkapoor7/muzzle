import XCTest
import Darwin
@testable import MuzzleHelper
import MuzzleService

final class SecurityTests: XCTestCase {
    func testSocketRoundTripAndClosedPeer() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { close(sockets[0]); close(sockets[1]) }
        sockets.forEach { SocketTransport.configure($0, timeout: 1) }
        try SocketTransport.write(ServiceRequest(.status), to: sockets[0])
        let decoded = try JSONDecoder().decode(ServiceRequest.self, from: SocketTransport.read(sockets[1]))
        XCTAssertEqual(decoded.version, ServicePaths.protocolVersion)
        shutdown(sockets[0], SHUT_WR)
        XCTAssertThrowsError(try SocketTransport.read(sockets[1]))
    }

    func testRejectsOversizedMessagesAndSocketPaths() throws {
        XCTAssertThrowsError(try SocketTransport.address(String(repeating: "a", count: 200)))
        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { return XCTFail("Could not create socket pair") }
        defer { close(sockets[0]); close(sockets[1]) }
        sockets.forEach { SocketTransport.configure($0, timeout: 1) }
        XCTAssertThrowsError(try SocketTransport.write(String(repeating: "a", count: SocketTransport.maxBytes), to: sockets[0])) {
            XCTAssertEqual($0.localizedDescription, "Service message exceeds the size limit.")
        }
    }

    func testStagedHelperMustMatchCapturedNestedIdentity() throws {
        let original = URL(fileURLWithPath: "/usr/bin/true")
        let replacement = URL(fileURLWithPath: "/usr/bin/false")
        let identity = try HelperSignature.identity(of: original)
        XCTAssertNoThrow(try HelperSignature.validate(original, identity: identity))
        XCTAssertThrowsError(try HelperSignature.validate(replacement, identity: identity)) {
            XCTAssertEqual($0.localizedDescription, "The staged helper does not match the validated nested helper.")
        }
    }

    func testRejectsWrongUIDAndUnapprovedCode() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { close(sockets[0]); close(sockets[1]) }
        XCTAssertTrue(PeerAuthentication.validate(fd: sockets[1], config:
            ServiceConfiguration(ownerUID: getuid(), clientRequirement: "always")))
        XCTAssertFalse(PeerAuthentication.validate(fd: sockets[1], config:
            ServiceConfiguration(ownerUID: getuid() + 1, clientRequirement: "always")))
        XCTAssertFalse(PeerAuthentication.validate(fd: sockets[1], config:
            ServiceConfiguration(ownerUID: getuid(), clientRequirement: "identifier \"local.muzzle.app\" and cdhash H\"0000000000000000000000000000000000000000\"")))
    }

    func testRootFilesRejectSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/etc/hosts")
        XCTAssertThrowsError(try RootFiles.check(link.path))
        if getuid() != 0 { XCTAssertThrowsError(try RootFiles.check(directory.path, directory: true)) }
    }
}
