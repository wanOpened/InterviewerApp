import Combine
import Foundation

@MainActor
final class AuthGate: ObservableObject {
    @Published private(set) var isLoggedIn: Bool

    private let tokenStore: TokenStore
    private let now: () -> Date

    init(
        tokenStore: TokenStore,
        now: @escaping () -> Date = Date.init,
        forceLoggedIn: Bool = false
    ) {
        self.tokenStore = tokenStore
        self.now = now
        self.isLoggedIn = forceLoggedIn || tokenStore.isLoggedIn
    }

    func login(_ response: AuthTokenResponse) {
        tokenStore.save(
            access: response.accessToken,
            refresh: response.refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(response.expiresInSeconds))
        )
        isLoggedIn = true
    }

    func logout() {
        tokenStore.clear()
        isLoggedIn = false
    }
}
