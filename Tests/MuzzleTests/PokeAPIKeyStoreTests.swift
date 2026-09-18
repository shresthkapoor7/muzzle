import XCTest
@testable import Muzzle

final class PokeAPIKeyStoreTests: XCTestCase {
    @MainActor
    func testExplicitlyMainActorCallbacks() throws {
        let backend = MainActorKeyBackend()
        let store = PokeAPIKeyStore(readKey: backend.read, writeKey: backend.write, deleteKey: backend.remove)
        XCTAssertEqual(store.apiKey(), "initial-token")
        try store.save("updated-token")
        XCTAssertEqual(backend.key, "updated-token")
        try store.remove()
        XCTAssertNil(backend.key)
        XCTAssertFalse(store.isConfigured)
    }

    @MainActor
    func testConfigurationAndRepeatedSendsShareOneKeychainRead() {
        var reads = 0
        let store = PokeAPIKeyStore(readKey: { reads += 1; return "test-token" },
                                   writeKey: { _ in XCTFail("Unexpected write") },
                                   deleteKey: { XCTFail("Unexpected delete") })
        XCTAssertTrue(store.isConfigured)
        for _ in 0..<5 { XCTAssertEqual(store.apiKey(), "test-token") }
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testSaveReplacesCachedTokenWithoutReadingAgain() throws {
        var reads = 0
        var stored: String?
        let store = PokeAPIKeyStore(readKey: { reads += 1; return nil },
                                   writeKey: { stored = $0 }, deleteKey: {})
        XCTAssertFalse(store.isConfigured)
        try store.save("  new-token\n")
        XCTAssertEqual(stored, "new-token")
        XCTAssertEqual(store.apiKey(), "new-token")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(reads, 1)
        try store.save("replacement-token")
        XCTAssertEqual(store.apiKey(), "replacement-token")
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testFailedMutationsRetainCacheAndSuccessfulRemovalClearsIt() throws {
        var stored: String? = "original-token"
        var failDeletion = true
        let store = PokeAPIKeyStore(readKey: { stored },
                                   writeKey: { _ in throw CocoaError(.fileWriteNoPermission) },
                                   deleteKey: {
            if failDeletion { throw CocoaError(.fileWriteNoPermission) }
            stored = nil
        })
        XCTAssertThrowsError(try store.save("replacement-token"))
        XCTAssertThrowsError(try store.remove())
        XCTAssertEqual(store.apiKey(), "original-token")
        XCTAssertTrue(store.isConfigured)
        failDeletion = false
        try store.remove()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.apiKey())
    }

    @MainActor
    func testDeniedReadCanBeRetriedAndThenCached() {
        var reads = 0
        let store = PokeAPIKeyStore(readKey: {
            reads += 1
            return reads == 1 ? nil : "authorized-token"
        }, writeKey: { _ in }, deleteKey: {})
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(store.apiKey(), "authorized-token")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.apiKey(), "authorized-token")
        XCTAssertEqual(reads, 2)
    }
}

@MainActor
private final class MainActorKeyBackend {
    var key: String? = "initial-token"
    func read() -> String? { key }
    func write(_ value: String) throws { key = value }
    func remove() throws { key = nil }
}
