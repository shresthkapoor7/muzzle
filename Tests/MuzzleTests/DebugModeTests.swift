import XCTest
@testable import Muzzle

final class DebugModeTests: XCTestCase {
    func testEnablesOnlyForDebugArgument() {
        XCTAssertTrue(DebugMode.isEnabled(arguments: ["Muzzle", "--debug"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle"]))
        XCTAssertFalse(DebugMode.isEnabled(arguments: ["Muzzle", "--debugging"]))
    }

    @MainActor
    func testDebugProfileUsesSeparateRuleAndStorageNames() {
        XCTAssertEqual(BlockingProfile.debug.applicationSupportDirectoryName, "Muzzle Debug")
        XCTAssertEqual(BlockingProfile.debug.hostsOpeningMarker, "# MUZZLE_DEBUG_BEGIN — managed by Muzzle Debug")
        XCTAssertEqual(BlockingProfile.debug.packetFilterAnchorFileName, "muzzle-debug")
        XCTAssertEqual(BlockingProfile.debug.packetFilterAnchorName, "com.apple/muzzle-debug")
    }

    func testDebugPacketFilterCommandsUseOnlyTheDebugAnchor() {
        let controller = PacketFilterController(profile: .debug)
        let anchor = URL(fileURLWithPath: "/tmp/muzzle-debug")
        let install = controller.installCommand(anchor: anchor, ipv4Addresses: ["203.0.113.10"], ipv6Addresses: [])

        XCTAssertTrue(install.contains("/etc/pf.anchors/muzzle-debug"))
        XCTAssertTrue(install.contains("-a com.apple/muzzle-debug"))
        XCTAssertFalse(install.contains("com.apple/websiteblocker"))
        XCTAssertFalse(controller.removeCommand().contains("com.apple/websiteblocker"))
    }
}
