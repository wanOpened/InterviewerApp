import XCTest
@testable import InterviewerApp

@MainActor
final class LoginViewModelTests: XCTestCase {
    func test_normalizePhoneAndValidation() {
        XCTAssertEqual(LoginViewModel.normalizePhone("138 1234 5678"), "13812345678")
        XCTAssertEqual(LoginViewModel.normalizePhone("+8613812345678"), "13812345678")

        let model = makeModel()
        model.phone = "13812345678"
        XCTAssertTrue(model.isPhoneValid)

        model.phone = "12812345678"
        XCTAssertFalse(model.isPhoneValid)

        model.phone = "1381234567"
        XCTAssertFalse(model.isPhoneValid)
    }

    func test_requestCodeSuccessStoresChallengeAndStartsCountdown() async {
        let service = FakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        let model = makeModel(service: service)
        model.phone = "+8613812345678"

        await model.requestCode()

        XCTAssertEqual(service.requestedPhones, ["13812345678"])
        XCTAssertEqual(model.challengeId, "challenge-1")
        XCTAssertEqual(model.phase, .codeSent)
        XCTAssertEqual(model.resendCountdown, 60)
        XCTAssertFalse(model.canResend)
    }

    func test_tickReEnablesResendWhenCountdownReachesZero() async {
        let service = FakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 2,
            devCode: nil
        )
        let model = makeModel(service: service)
        model.phone = "13812345678"
        await model.requestCode()

        model.tick()
        XCTAssertEqual(model.resendCountdown, 1)
        XCTAssertFalse(model.canResend)
        XCTAssertEqual(model.codeButtonTitle, "1s 重发")

        model.tick()
        XCTAssertEqual(model.resendCountdown, 0)
        XCTAssertTrue(model.canResend)
        XCTAssertEqual(model.codeButtonTitle, "获取验证码")
    }

    func test_verifySuccessSavesTokensAndCallsLoggedInCallback() async {
        let service = FakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        service.verifyResponse = authTokenResponse()
        let store = makeTokenStore(now: Date(timeIntervalSince1970: 100))
        let model = makeModel(service: service, tokenStore: store, now: { Date(timeIntervalSince1970: 100) })
        var loggedInResponse: AuthTokenResponse?
        model.onLoggedIn = { loggedInResponse = $0 }
        model.phone = "13812345678"
        model.code = "123456"
        await model.requestCode()

        await model.verify()

        XCTAssertEqual(service.verifiedRequests, [
            FakeAuthService.VerifyRequest(challengeId: "challenge-1", phone: "13812345678", code: "123456")
        ])
        XCTAssertEqual(store.accessToken, "access-token")
        XCTAssertEqual(store.refreshToken, "refresh-token")
        XCTAssertEqual(store.expiresAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(model.phase, .loggedIn)
        XCTAssertEqual(loggedInResponse?.accessToken, "access-token")
    }

    func test_verifyFailureShowsAPIErrorAndDoesNotSaveToken() async {
        let service = FakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        service.verifyError = APIError(
            status: 401,
            errorCode: "AUTH_CODE_INVALID",
            userMessage: "验证码不正确",
            traceId: nil,
            retryAfter: nil
        )
        let store = makeTokenStore()
        let model = makeModel(service: service, tokenStore: store)
        model.phone = "13812345678"
        model.code = "0000"
        await model.requestCode()

        await model.verify()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.errorMessage, "验证码不正确")
        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.refreshToken)
    }

    func test_requestCodeRateLimitShowsBackendMessageAndReturnsToRetryableState() async {
        let service = FakeAuthService()
        service.requestError = APIError(
            status: 429,
            errorCode: "AUTH_CODE_RATE_LIMITED",
            userMessage: "操作过于频繁，请稍后再试。",
            traceId: nil,
            retryAfter: 60
        )
        let model = makeModel(service: service)
        model.phone = "13812345678"

        await model.requestCode()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.errorMessage, "操作过于频繁，请稍后再试。")
        XCTAssertTrue(model.canResend)
    }

    func test_codeIsSanitizedToDigitsOnlyAndCappedAtSix() async {
        let service = FakeAuthService()
        service.phoneCodeResponse = PhoneCodeResponse(
            challengeId: "challenge-1",
            expiresInSeconds: 300,
            resendAfterSeconds: 60,
            devCode: nil
        )
        service.verifyResponse = authTokenResponse()
        let model = makeModel(service: service)

        model.code = "12 34-56"
        XCTAssertEqual(model.code, "123456")

        model.code = "abc123def456"
        XCTAssertEqual(model.code, "123456")

        model.phone = "13812345678"
        model.code = "1 2 3 4 5 6"
        await model.requestCode()
        await model.verify()

        XCTAssertEqual(service.verifiedRequests.last?.code, "123456")
    }

    func test_submitEnabledRequiresValidPhoneCodeAndNotVerifying() {
        let model = makeModel()
        model.phone = "13812345678"
        model.code = "1234"
        XCTAssertTrue(model.isSubmitEnabled)

        model.phone = "12812345678"
        XCTAssertFalse(model.isSubmitEnabled)

        model.phone = "13812345678"
        model.code = "123"
        XCTAssertFalse(model.isSubmitEnabled)

        model.code = "1234"
        model.phase = .verifying
        XCTAssertFalse(model.isSubmitEnabled)
    }

    private func makeModel(
        service: FakeAuthService = FakeAuthService(),
        tokenStore: TokenStore? = nil,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 100) }
    ) -> LoginViewModel {
        LoginViewModel(
            authService: service,
            tokenStore: tokenStore ?? makeTokenStore(now: now()),
            now: now,
            startsTimerAutomatically: false
        )
    }

    private func makeTokenStore(now: Date = Date(timeIntervalSince1970: 100)) -> TokenStore {
        let suiteName = "LoginViewModelTests.\(UUID().uuidString)"
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

private final class FakeAuthService: AuthServicing {
    struct VerifyRequest: Equatable {
        let challengeId: String
        let phone: String
        let code: String
    }

    var phoneCodeResponse = PhoneCodeResponse(
        challengeId: "challenge-default",
        expiresInSeconds: 300,
        resendAfterSeconds: 60,
        devCode: nil
    )
    var verifyResponse: AuthTokenResponse?
    var requestError: Error?
    var verifyError: Error?
    var requestedPhones: [String] = []
    var verifiedRequests: [VerifyRequest] = []

    func requestPhoneCode(phone: String) async throws -> PhoneCodeResponse {
        requestedPhones.append(phone)
        if let requestError { throw requestError }
        return phoneCodeResponse
    }

    func verifyPhoneCode(challengeId: String, phone: String, code: String) async throws -> AuthTokenResponse {
        verifiedRequests.append(VerifyRequest(challengeId: challengeId, phone: phone, code: code))
        if let verifyError { throw verifyError }
        return verifyResponse!
    }
}
