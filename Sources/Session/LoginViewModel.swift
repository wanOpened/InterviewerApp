import Combine
import Foundation

protocol AuthServicing {
    func requestPhoneCode(phone: String) async throws -> PhoneCodeResponse
    func verifyPhoneCode(challengeId: String, phone: String, code: String) async throws -> AuthTokenResponse
}

extension APIClient: AuthServicing {}

@MainActor
final class LoginViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingCode
        case codeSent
        case verifying
        case loggedIn
        case error
    }

    @Published var phone = ""
    @Published var code = "" {
        didSet {
            // The backend hashes the raw code as-is (no strip), so a stray space /
            // newline from the keyboard or OTP autofill would be rejected as
            // AUTH_CODE_INVALID. Keep only digits and cap at the 6-digit code length.
            let sanitized = String(code.filter(\.isNumber).prefix(6))
            if sanitized != code {
                code = sanitized
            }
        }
    }
    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
    @Published var resendCountdown = 0

    private let authService: AuthServicing
    private let tokenStore: TokenStore
    private let now: () -> Date
    private let startsTimerAutomatically: Bool
    private var timer: Timer?

    private(set) var challengeId: String?
    var onLoggedIn: ((AuthTokenResponse) -> Void)?

    init(
        authService: AuthServicing,
        tokenStore: TokenStore,
        now: @escaping () -> Date = Date.init,
        startsTimerAutomatically: Bool = true
    ) {
        self.authService = authService
        self.tokenStore = tokenStore
        self.now = now
        self.startsTimerAutomatically = startsTimerAutomatically
    }

    deinit {
        timer?.invalidate()
    }

    var normalizedPhone: String {
        Self.normalizePhone(phone)
    }

    var isPhoneValid: Bool {
        Self.isValidPhone(normalizedPhone)
    }

    var canResend: Bool {
        resendCountdown == 0 && phase != .requestingCode
    }

    var codeButtonTitle: String {
        resendCountdown > 0 ? "\(resendCountdown)s 重发" : "获取验证码"
    }

    var isSubmitEnabled: Bool {
        isPhoneValid && code.count >= 4 && phase != .verifying
    }

    static func normalizePhone(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        if digits.hasPrefix("86"), digits.count == 13 {
            digits.removeFirst(2)
        }
        return String(digits)
    }

    static func isValidPhone(_ value: String) -> Bool {
        guard value.count == 11,
              value.first == "1",
              let second = value.dropFirst().first,
              "3456789".contains(second)
        else {
            return false
        }
        return value.allSatisfy(\.isNumber)
    }

    func requestCode() async {
        guard isPhoneValid, canResend else { return }

        phase = .requestingCode
        errorMessage = nil

        do {
            let response = try await authService.requestPhoneCode(phone: normalizedPhone)
            challengeId = response.challengeId
            resendCountdown = response.resendAfterSeconds
            phase = .codeSent
            #if DEBUG
            if let devCode = response.devCode {
                code = devCode
            }
            #endif
            startCountdownTimerIfNeeded()
        } catch {
            phase = .idle
            errorMessage = userFacingMessage(for: error)
        }
    }

    func resend() async {
        await requestCode()
    }

    func verify() async {
        guard isSubmitEnabled else { return }
        guard let challengeId else {
            phase = .error
            errorMessage = "请先获取验证码"
            return
        }

        phase = .verifying
        errorMessage = nil

        do {
            let response = try await authService.verifyPhoneCode(
                challengeId: challengeId,
                phone: normalizedPhone,
                code: code
            )
            tokenStore.save(
                access: response.accessToken,
                refresh: response.refreshToken,
                expiresAt: now().addingTimeInterval(TimeInterval(response.expiresInSeconds))
            )
            phase = .loggedIn
            onLoggedIn?(response)
        } catch {
            phase = .error
            errorMessage = userFacingMessage(for: error)
        }
    }

    func tick() {
        guard resendCountdown > 0 else {
            timer?.invalidate()
            timer = nil
            return
        }
        resendCountdown -= 1
        if resendCountdown == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startCountdownTimerIfNeeded() {
        timer?.invalidate()
        guard startsTimerAutomatically, resendCountdown > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        return "网络异常，请重试"
    }
}
