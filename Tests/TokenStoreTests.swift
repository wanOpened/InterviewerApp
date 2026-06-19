import XCTest
@testable import InterviewerApp

final class TokenStoreTests: XCTestCase {
    func test_savePersistsTokensAndLoginState() {
        let defaults = makeDefaults()
        let store = TokenStore(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })

        store.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(store.accessToken, "access-token")
        XCTAssertEqual(store.refreshToken, "refresh-token")
        XCTAssertEqual(store.expiresAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(store.isLoggedIn)
    }

    func test_clearRemovesTokensAndLoginState() {
        let defaults = makeDefaults()
        let store = TokenStore(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        store.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        store.clear()

        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.refreshToken)
        XCTAssertNil(store.expiresAt)
        XCTAssertFalse(store.isLoggedIn)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TokenStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
