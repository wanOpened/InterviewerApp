import XCTest
@testable import InterviewerApp

@MainActor
final class AuthGateTests: XCTestCase {
    func test_validAccessTokenStartsLoggedIn() {
        let store = makeTokenStore(now: Date(timeIntervalSince1970: 100))
        store.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 200)
        )

        let gate = AuthGate(tokenStore: store)

        XCTAssertTrue(gate.isLoggedIn)
    }

    func test_missingAccessTokenStartsLoggedOut() {
        let gate = AuthGate(tokenStore: makeTokenStore())

        XCTAssertFalse(gate.isLoggedIn)
    }

    func test_expiredAccessTokenStartsLoggedOut() {
        let store = makeTokenStore(now: Date(timeIntervalSince1970: 200))
        store.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        let gate = AuthGate(tokenStore: store)

        XCTAssertFalse(gate.isLoggedIn)
    }

    func test_loginSavesTokensAndMarksLoggedIn() {
        let now = Date(timeIntervalSince1970: 100)
        let store = makeTokenStore(now: now)
        let gate = AuthGate(tokenStore: store, now: { now })

        gate.login(authTokenResponse())

        XCTAssertTrue(gate.isLoggedIn)
        XCTAssertEqual(store.accessToken, "access-token")
        XCTAssertEqual(store.refreshToken, "refresh-token")
        XCTAssertEqual(store.expiresAt, Date(timeIntervalSince1970: 1_000))
    }

    func test_logoutClearsTokensAndMarksLoggedOut() {
        let store = makeTokenStore(now: Date(timeIntervalSince1970: 100))
        store.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let gate = AuthGate(tokenStore: store)

        gate.logout()

        XCTAssertFalse(gate.isLoggedIn)
        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.refreshToken)
        XCTAssertNil(store.expiresAt)
    }

    private func makeTokenStore(now: Date = Date(timeIntervalSince1970: 100)) -> TokenStore {
        let suiteName = "AuthGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TokenStore(defaults: defaults, now: { now })
    }

    private func authTokenResponse() -> AuthTokenResponse {
        AuthTokenResponse(
            tokenType: "bearer",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresInSeconds: 900,
            user: CurrentUserRead(
                id: "user-1",
                phoneMasked: "138****5678",
                profile: UserProfileRead(
                    displayName: nil,
                    timezone: "Asia/Shanghai",
                    preferredCompanion: "qinglan",
                    targetSummary: nil,
                    weaknessSummary: nil,
                    memoryUpdatedAt: nil
                )
            )
        )
    }
}
