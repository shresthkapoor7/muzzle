import XCTest
import AppKit
import MuzzleService
@testable import Muzzle

final class StatusMenuTests: XCTestCase {
    @MainActor
    func testServiceSetupAndActiveSessionMenu() {
        let blocker = BlockerController()
        let controller = StatusItemController(
            blocker: blocker, isDebugMode: false, onManage: {}, onEndSession: {},
            onBypass: {}, onRequestBypass: {}, onRedeemBypass: {}, onRetrySystemUpdate: {},
            onQuit: {}, onCheckForUpdates: {}, onInstallService: {}
        )
        XCTAssertTrue(controller.makeMenu().items.contains { $0.title == "Set Up Blocking Service…" })

        var snapshot = ServiceSnapshot()
        snapshot.domains = ["example.com"]
        snapshot.sessionID = UUID()
        snapshot.isEnforced = true
        blocker.acceptServiceResponse(ServiceResponse(snapshot: snapshot))
        let activeItems = controller.makeMenu().items
        XCTAssertTrue(activeItems.contains { $0.title == "Blocking service: running" && !$0.isEnabled })
        XCTAssertFalse(activeItems.contains { $0.title.contains("Set Up") || $0.title.contains("Install / Update") })
        XCTAssertFalse(activeItems.contains { $0.title.hasPrefix("Quit Muzzle") })

        snapshot.bypassEndsAt = Date().addingTimeInterval(60)
        blocker.acceptServiceResponse(ServiceResponse(snapshot: snapshot))
        XCTAssertFalse(controller.makeMenu().items.contains { $0.title.hasPrefix("Quit Muzzle") })

        blocker.acceptServiceResponse(ServiceResponse(snapshot: ServiceSnapshot()))
        XCTAssertTrue(controller.makeMenu().items.contains { $0.title == "Quit Muzzle" })
    }
}
