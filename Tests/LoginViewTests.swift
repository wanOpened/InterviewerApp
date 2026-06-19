import SwiftUI
import XCTest
@testable import InterviewerApp

@MainActor
final class LoginViewTests: XCTestCase {
    func test_requestCodeFromLoginViewModelMovesToCodeSentState() async {
        let service = LoginViewFakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        let model = makeModel(service: service)
        _ = LoginView(model: model)
        model.phone = "13812345678"

        await model.requestCode()

        XCTAssertEqual(model.phase, .codeSent)
        XCTAssertEqual(model.resendCountdown, 60)
        XCTAssertEqual(service.requestedPhones, ["13812345678"])
    }

    func test_verifyFromLoginViewModelMovesToLoggedInState() async {
        let service = LoginViewFakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        service.verifyResponse = authTokenResponse()
        let model = makeModel(service: service)
        _ = LoginView(model: model)
        model.phone = "13812345678"
        model.code = "123456"
        await model.requestCode()

        await model.verify()

        XCTAssertEqual(model.phase, .loggedIn)
        XCTAssertEqual(service.verifiedCodes, ["123456"])
    }

    private func makeModel(service: LoginViewFakeAuthService) -> LoginViewModel {
        let suiteName = "LoginViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LoginViewModel(
            authService: service,
            tokenStore: TokenStore(defaults: defaults, now: { Date(timeIntervalSince1970: 100) }),
            now: { Date(timeIntervalSince1970: 100) },
            startsTimerAutomatically: false
        )
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

private final class LoginViewFakeAuthService: AuthServicing {
    var phoneCodeResponse = PhoneCodeResponse(
        challengeId: "challenge-default",
        expiresInSeconds: 300,
        resendAfterSeconds: 60,
        devCode: nil
    )
    var verifyResponse: AuthTokenResponse?
    var requestedPhones: [String] = []
    var verifiedCodes: [String] = []

    func requestPhoneCode(phone: String) async throws -> PhoneCodeResponse {
        requestedPhones.append(phone)
        return phoneCodeResponse
    }

    func verifyPhoneCode(challengeId: String, phone: String, code: String) async throws -> AuthTokenResponse {
        verifiedCodes.append(code)
        return verifyResponse!
    }
}
