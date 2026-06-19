import XCTest
@testable import InterviewerApp

final class AuthModelsTests: XCTestCase {
    func test_phoneCodeResponseDecodesSnakeCaseContract() throws {
        let json = """
        {
          "challenge_id": "challenge-123",
          "expires_in_seconds": 300,
          "resend_after_seconds": 60,
          "dev_code": "123456"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PhoneCodeResponse.self, from: json)

        XCTAssertEqual(response.challengeId, "challenge-123")
        XCTAssertEqual(response.expiresInSeconds, 300)
        XCTAssertEqual(response.resendAfterSeconds, 60)
        XCTAssertEqual(response.devCode, "123456")
    }

    func test_authTokenResponseDecodesUserAndProfile() throws {
        let json = """
        {
          "token_type": "bearer",
          "access_token": "access-token",
          "refresh_token": "refresh-token",
          "expires_in_seconds": 900,
          "user": {
            "id": "user-1",
            "phone_masked": "138****5678",
            "profile": {
              "display_name": "Qinglan Tester",
              "timezone": "Asia/Shanghai",
              "preferred_companion": "qinglan",
              "target_summary": "iOS interviews",
              "weakness_summary": "system design",
              "memory_updated_at": "2026-06-16T08:00:00Z"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthTokenResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "access-token")
        XCTAssertEqual(response.refreshToken, "refresh-token")
        XCTAssertEqual(response.user.phoneMasked, "138****5678")
        XCTAssertEqual(response.user.profile.timezone, "Asia/Shanghai")
    }
}
