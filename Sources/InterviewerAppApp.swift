import SwiftUI

@main
struct InterviewerAppApp: App {
    var body: some Scene {
        WindowGroup {
            if DesignGalleryGate.isEnabled {
                DesignGalleryRootView()
            } else {
                AuthRootView()
            }
        }
    }
}

@MainActor
private struct AuthRootView: View {
    @StateObject private var authGate: AuthGate
    @StateObject private var loginModel: LoginViewModel
    private let tokenStore: TokenStore

    init(
        config: AppConfig = .load(),
        tokenStore: TokenStore = TokenStore(),
        forceLoggedIn: Bool = ProcessInfo.processInfo.arguments.contains("-UITestLoggedIn")
    ) {
        let api = APIClient(
            baseURL: config.apiBaseURL,
            userExternalId: config.devUserExternalId,
            tokenProvider: tokenStore
        )
        let gate = AuthGate(tokenStore: tokenStore, forceLoggedIn: forceLoggedIn)
        let model = LoginViewModel(authService: api, tokenStore: tokenStore)
        model.onLoggedIn = { [weak gate] response in
            gate?.login(response)
        }

        self.tokenStore = tokenStore
        _authGate = StateObject(wrappedValue: gate)
        _loginModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        if authGate.isLoggedIn {
            HomeView(tokenProvider: tokenStore)
        } else {
            LoginView(model: loginModel)
        }
    }
}
