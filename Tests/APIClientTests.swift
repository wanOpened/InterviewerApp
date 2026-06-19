import XCTest
@testable import InterviewerApp

final class APIErrorTests: XCTestCase {
    func test_decodesBackendErrorEnvelope() throws {
        let json = """
        {"type":"x","title":"Rate Limited","status":429,
         "error_code":"RATE_LIMITED","error_code_family":"RATE_LIMIT",
         "user_message":"操作过于频繁，请稍后再试。","trace_id":"t-1",
         "retry_after":86400,"details":{}}
        """.data(using: .utf8)!
        let err = try JSONDecoder().decode(APIError.self, from: json)
        XCTAssertEqual(err.errorCode, "RATE_LIMITED")
        XCTAssertEqual(err.userMessage, "操作过于频繁，请稍后再试。")
        XCTAssertEqual(err.retryAfter, 86400)
        XCTAssertEqual(err.traceId, "t-1")
    }
}

final class APIClientTests: XCTestCase {
    /// Captures the last request and returns a canned response.
    func makeClient(_ status: Int, _ body: Data) -> (APIClient, () -> URLRequest?) {
        var captured: URLRequest?
        let client = APIClient(
            baseURL: URL(string: "http://host:8000")!,
            userExternalId: "u-1"
        ) { request in
            captured = request
            let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }
        return (client, { captured })
    }

    func test_liveKitJoinTokenPolicyDetectsObserveToken() throws {
        let token = jwt(payload: #"{"video":{"canPublish":false},"roomConfig":{"metadata":"{\"session_id\":\"s-1\",\"purpose\":\"observe_interview\"}"}}"#)

        let policy = LiveKitJoinTokenPolicy(token: token)

        XCTAssertFalse(policy.canPublish)
        XCTAssertEqual(policy.purpose, "observe_interview")
        XCTAssertTrue(policy.isObserveInterview)
    }

    func test_liveKitJoinTokenPolicyDefaultsToInterviewPublishing() throws {
        let token = jwt(payload: #"{"video":{"canPublish":true},"roomConfig":{"metadata":"{\"session_id\":\"s-1\"}"}}"#)

        let policy = LiveKitJoinTokenPolicy(token: token)

        XCTAssertTrue(policy.canPublish)
        XCTAssertNil(policy.purpose)
        XCTAssertFalse(policy.isObserveInterview)
    }

    func test_createSession_setsHeadersAndBody() async throws {
        let body = #"{"id":"s-1","status":"created","livekit_room":null,"failure_reason":null,"total_cost_usd":null}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(201, body)
        let session = try await client.createSession(positionRoundId: "pr-1", companion: .xingyu)
        XCTAssertEqual(session.id, "s-1")
        let req = lastRequest()!
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-User-Id"), "u-1")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(req.url?.path, "/v1/sessions")
        XCTAssertEqual(req.httpMethod, "POST")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["companion"] as? String, "xingyu")
    }

    func test_ensureResumeDoesNotCreatePlaceholderWhenResumeIsMissing() async throws {
        var requests: [URLRequest] = []
        let client = APIClient(
            baseURL: URL(string: "http://host:8000")!,
            userExternalId: "u-1"
        ) { request in
            requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        do {
            try await client.ensureResume()
            XCTFail("expected missing resume error")
        } catch is ResumeRequiredError {
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.httpMethod, "GET")
        }
    }

    func test_createResumePostsUserProvidedText() async throws {
        let body = #"{"id":"r-1","version":1,"is_current":true,"raw_text":"真实的项目和工作经历","created_at":"2026-06-03T12:00:00Z"}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(201, body)

        let resume = try await client.createResume(rawText: "真实的项目和工作经历")

        XCTAssertEqual(resume.id, "r-1")
        XCTAssertEqual(resume.raw_text, "真实的项目和工作经历")
        XCTAssertEqual(resume.created_at, "2026-06-03T12:00:00Z")
        let requestBody = try JSONSerialization.jsonObject(with: lastRequest()!.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["raw_text"] as? String, "真实的项目和工作经历")
    }

    func test_scheduleDetailDecodesSchedulePositionRoundAndResumeFields() throws {
        let body = """
        {"schedule":{"id":"sch-1","position_round_id":"pr-1",
         "scheduled_at":"2026-06-10T15:00:00+08:00","timezone":"Asia/Shanghai",
         "duration_minutes":45,"status":"scheduled","session_id":null,
         "raw_command":"下周二字节终面","created_at":"2026-06-09T12:00:00Z",
         "position_title":"产品经理","company":"字节","round_name":"终面"},
         "position":{"id":"p-1","title":"产品经理","company":"字节",
         "jd_text":"负责 AI 搜索产品。","seniority":"senior","created_at":"2026-06-01T12:00:00Z"},
         "round":{"id":"r-1","round_name":"终面"},
         "resume":{"id":"res-1","version":3,"is_current":true,
         "raw_text":"候选人简历正文","created_at":"2026-05-01T12:00:00Z"}}
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(ScheduleDetailRead.self, from: body)

        XCTAssertEqual(detail.schedule.position_title, "产品经理")
        XCTAssertEqual(detail.schedule.company, "字节")
        XCTAssertEqual(detail.schedule.round_name, "终面")
        XCTAssertEqual(detail.position.jd_text, "负责 AI 搜索产品。")
        XCTAssertEqual(detail.position.seniority, "senior")
        XCTAssertEqual(detail.position.created_at, "2026-06-01T12:00:00Z")
        XCTAssertEqual(detail.round.round_name, "终面")
        XCTAssertEqual(detail.resume?.raw_text, "候选人简历正文")
        XCTAssertEqual(detail.resume?.created_at, "2026-05-01T12:00:00Z")
    }

    func test_scheduleDetailGetsScheduleDetailEndpoint() async throws {
        let body = """
        {"schedule":{"id":"sch-1","position_round_id":"pr-1",
         "scheduled_at":"2026-06-10T15:00:00+08:00","timezone":"Asia/Shanghai",
         "duration_minutes":45,"status":"scheduled","session_id":null,
         "raw_command":"下周二字节终面","created_at":"2026-06-09T12:00:00Z",
         "position_title":"产品经理","company":"字节","round_name":"终面"},
         "position":{"id":"p-1","title":"产品经理","company":"字节",
         "jd_text":"负责 AI 搜索产品。","seniority":null,"created_at":"2026-06-01T12:00:00Z"},
         "round":{"id":"r-1","round_name":"终面"},
         "resume":null}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let detail = try await client.scheduleDetail(id: "sch-1")

        XCTAssertEqual(detail.schedule.id, "sch-1")
        XCTAssertNil(detail.resume)
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/interview-schedules/sch-1")
        XCTAssertEqual(req.httpMethod, "GET")
    }

    func test_getCurrentResumeGetsResumeMeEndpoint() async throws {
        let body = #"{"id":"r-2","version":4,"is_current":true,"raw_text":"新版简历正文","created_at":"2026-06-08T12:00:00Z"}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let resume = try await client.getCurrentResume()

        XCTAssertEqual(resume.id, "r-2")
        XCTAssertEqual(resume.raw_text, "新版简历正文")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/resumes/me")
        XCTAssertEqual(req.httpMethod, "GET")
    }

    func test_parseScheduleDraft_postsVoiceCommandAndTimezone() async throws {
        let body = """
        {"id":"d-1","raw_input":"帮我约明天下午三点产品二面","intent":"create_schedule",
         "action":"confirm","confidence":0.92,"assistant_message":"确认约在明天下午三点？",
         "position_round_id":"pr-1","scheduled_at":"2026-06-03T15:00:00+08:00",
         "missing_fields":[],"validation_errors":[],"ambiguities":[],
         "pull_back_message":null,"suggested_replies":[],
         "normalized_slots":{"company":"字节","round_number":2},
         "status":"confirmable","expires_at":"2026-06-02T19:00:00Z","created_at":"2026-06-02T18:00:00Z"}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let draft = try await client.parseScheduleDraft(
            rawInput: "帮我约明天下午三点产品二面",
            timezone: "Asia/Shanghai"
        )

        XCTAssertEqual(draft.id, "d-1")
        XCTAssertEqual(draft.action, "confirm")
        XCTAssertEqual(draft.normalized_slots?["round_number"]?.intValue, 2)
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/schedule-drafts/parse")
        XCTAssertEqual(req.httpMethod, "POST")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["text"] as? String, "帮我约明天下午三点产品二面")
        XCTAssertEqual(requestBody?["timezone"] as? String, "Asia/Shanghai")
    }

    func test_updateScheduleDraft_patchesExistingDraftWithFollowupText() async throws {
        let body = """
        {"id":"d-2","raw_input":"明天练一下 下午三点产品二面","intent":"create_schedule",
         "action":"confirm","confidence":0.92,"assistant_message":"确认约在明天下午三点？",
         "position_round_id":"pr-1","scheduled_at":"2026-06-03T15:00:00+08:00",
         "missing_fields":[],"validation_errors":[],"ambiguities":[],
         "pull_back_message":null,"suggested_replies":[],"normalized_slots":{},
         "status":"confirmable","expires_at":"2026-06-02T19:00:00Z","created_at":"2026-06-02T18:00:00Z"}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let draft = try await client.updateScheduleDraft(
            id: "d-1",
            rawInput: "下午三点产品二面",
            timezone: "Asia/Shanghai"
        )

        XCTAssertEqual(draft.id, "d-2")
        XCTAssertEqual(draft.action, "confirm")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/schedule-drafts/d-1")
        XCTAssertEqual(req.httpMethod, "PATCH")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["text"] as? String, "下午三点产品二面")
        XCTAssertEqual(requestBody?["timezone"] as? String, "Asia/Shanghai")
    }

    func test_startSchedule_postsScheduleStartAndDecodesSession() async throws {
        let body = """
        {"schedule":{"id":"sch-1","position_round_id":"pr-1",
         "scheduled_at":"2026-06-03T15:00:00+08:00","timezone":"Asia/Shanghai",
         "duration_minutes":30,"status":"preparing","session_id":"s-1",
         "raw_command":"明天下午三点产品二面","created_at":"2026-06-02T18:00:00Z"},
         "session":{"id":"s-1","status":"questions_generating","livekit_room":null,
         "failure_reason":null,"total_cost_usd":null}}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let started = try await client.startSchedule(id: "sch-1", companion: .chengcheng)

        XCTAssertEqual(started.session.id, "s-1")
        XCTAssertEqual(started.schedule.session_id, "s-1")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/interview-schedules/sch-1/start")
        XCTAssertEqual(req.httpMethod, "POST")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["companion"] as? String, "chengcheng")
    }

    func test_updateSchedule_patchesTimeAndDuration() async throws {
        let body = """
        {"id":"sch-1","position_round_id":"pr-1",
         "scheduled_at":"2026-06-06T15:00:00Z","timezone":"Asia/Shanghai",
         "duration_minutes":45,"status":"scheduled","session_id":null,
         "raw_command":"明天下午三点产品二面","created_at":"2026-06-02T18:00:00Z"}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let schedule = try await client.updateSchedule(
            id: "sch-1",
            scheduledAt: "2026-06-06T15:00:00Z",
            timezone: "Asia/Shanghai",
            durationMinutes: 45
        )

        XCTAssertEqual(schedule.id, "sch-1")
        XCTAssertEqual(schedule.duration_minutes, 45)
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/interview-schedules/sch-1")
        XCTAssertEqual(req.httpMethod, "PATCH")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["scheduled_at"] as? String, "2026-06-06T15:00:00Z")
        XCTAssertEqual(requestBody?["timezone"] as? String, "Asia/Shanghai")
        XCTAssertEqual(requestBody?["duration_minutes"] as? Int, 45)
    }

    func test_cancelSchedule_postsCancelEndpoint() async throws {
        let body = """
        {"id":"sch-1","position_round_id":"pr-1",
         "scheduled_at":"2026-06-03T15:00:00+08:00","timezone":"Asia/Shanghai",
         "duration_minutes":30,"status":"cancelled","session_id":null,
         "raw_command":"明天下午三点产品二面","created_at":"2026-06-02T18:00:00Z"}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let schedule = try await client.cancelSchedule(id: "sch-1")

        XCTAssertEqual(schedule.status, "cancelled")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/interview-schedules/sch-1/cancel")
        XCTAssertEqual(req.httpMethod, "POST")
    }

    func test_agentHome_getsRecommendation() async throws {
        let body = """
        {"generated_at":"2026-06-03T12:00:00Z",
         "primary_action":{"type":"start_practice","title":"开始这场面试的针对练习",
         "spoken_prompt":"明天就要面试了，我们先做一轮针对练习。","reason":"临近面试且没有练习记录。",
         "cta":"开始练习","target":{"schedule_id":"sch-1","position_round_id":"pr-1"}},
         "signals":[{"type":"upcoming_interview","label":"明天面试","severity":"high"},
                    {"type":"no_practice","label":"尚未练习","severity":"high"}],
         "voice_suggestions":["开始练习","先来一轮"]}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let home = try await client.agentHome()

        XCTAssertEqual(home.primary_action.type, "start_practice")
        XCTAssertEqual(home.primary_action.target["schedule_id"], "sch-1")
        XCTAssertEqual(home.signals.map(\.type), ["upcoming_interview", "no_practice"])
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/agent-home")
        XCTAssertEqual(req.httpMethod, "GET")
    }

    func test_agentHomeSpeech_postsSelectedCompanionAndReturnsAudio() async throws {
        let audio = Data("RIFF-audio".utf8)
        let (client, lastRequest) = makeClient(200, audio)

        let result = try await client.agentHomeSpeech(
            text: "明天下午先练一轮。",
            companion: .chengcheng
        )

        XCTAssertEqual(result, audio)
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/agent-home/speech")
        XCTAssertEqual(req.httpMethod, "POST")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["text"] as? String, "明天下午先练一轮。")
        XCTAssertEqual(requestBody?["companion"] as? String, "chengcheng")
    }

    func test_joinHomeVoicePostsDedicatedHomeVoiceJoinEndpoint() async throws {
        let body = """
        {"session_id":"hv-1","livekit_room":"home-voice-hv-1","livekit_token":"home-token",
         "current_context":{"generated_at":"2026-06-07T12:00:00Z",
         "primary_action":{"type":"create_schedule","title":"创建日程",
         "spoken_prompt":"说出你想什么时候练。","reason":"先安排一次练习。",
         "cta":"创建","target":{}},
         "signals":[],"voice_suggestions":["明天下午三点产品二面"],"briefing_items":[]}}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let joined = try await client.joinHomeVoice()

        XCTAssertEqual(joined.livekit_room, "home-voice-hv-1")
        XCTAssertEqual(joined.current_context.primary_action.type, "create_schedule")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/home-voice/join")
        XCTAssertEqual(req.httpMethod, "POST")
    }

    func test_updatePositionJD_patchesJDText() async throws {
        let body = #"{"id":"p-1","title":"PM","company":"ByteDance","jd_text":"负责 AI 搜索产品。","seniority":null,"created_at":"2026-06-03T12:00:00Z"}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let position = try await client.updatePositionJD(positionId: "p-1", jdText: "负责 AI 搜索产品。")

        XCTAssertEqual(position.id, "p-1")
        XCTAssertEqual(position.jd_text, "负责 AI 搜索产品。")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/positions/p-1/jd")
        XCTAssertEqual(req.httpMethod, "PATCH")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["jd_text"] as? String, "负责 AI 搜索产品。")
    }

    func test_requestPhoneCodePostsAuthEndpointWithoutBearerToken() async throws {
        let body = """
        {"challenge_id":"challenge-1","expires_in_seconds":300,
         "resend_after_seconds":60,"dev_code":"123456"}
        """.data(using: .utf8)!
        let (client, lastRequest) = makeClient(200, body)

        let response = try await client.requestPhoneCode(phone: "13812345678")

        XCTAssertEqual(response.challengeId, "challenge-1")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/auth/phone/request-code")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["phone"] as? String, "13812345678")
    }

    func test_verifyPhoneCodePostsAuthEndpointAndDecodesTokenResponse() async throws {
        let (client, lastRequest) = makeClient(200, authTokenResponseBody())

        let response = try await client.verifyPhoneCode(
            challengeId: "challenge-1",
            phone: "13812345678",
            code: "123456"
        )

        XCTAssertEqual(response.accessToken, "access-token")
        XCTAssertEqual(response.refreshToken, "refresh-token")
        XCTAssertEqual(response.user.phoneMasked, "138****5678")
        let req = lastRequest()!
        XCTAssertEqual(req.url?.path, "/v1/auth/phone/verify")
        XCTAssertEqual(req.httpMethod, "POST")
        let requestBody = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(requestBody?["challenge_id"] as? String, "challenge-1")
        XCTAssertEqual(requestBody?["phone"] as? String, "13812345678")
        XCTAssertEqual(requestBody?["code"] as? String, "123456")
    }

    func test_authenticatedRequestAddsBearerAuthorizationHeader() async throws {
        let defaults = UserDefaults(suiteName: "APIClientTests.\(UUID().uuidString)")!
        let tokenStore = TokenStore(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        tokenStore.save(
            access: "access-token",
            refresh: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
        let body = #"{"id":"s-1","status":"created","livekit_room":null,"failure_reason":null,"total_cost_usd":null}"#.data(using: .utf8)!
        var captured: URLRequest?
        let client = APIClient(
            baseURL: URL(string: "http://host:8000")!,
            userExternalId: "u-1",
            tokenProvider: tokenStore
        ) { request in
            captured = request
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, resp)
        }

        _ = try await client.createSession(positionRoundId: "pr-1", companion: .qinglan)

        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func test_unauthenticatedRequestKeepsDevUserHeader() async throws {
        let body = #"{"id":"s-1","status":"created","livekit_room":null,"failure_reason":null,"total_cost_usd":null}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(201, body)

        _ = try await client.createSession(positionRoundId: "pr-1", companion: .qinglan)

        let req = lastRequest()!
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-User-Id"), "u-1")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func test_non2xx_throwsDecodedAPIError() async throws {
        let body = #"{"status":429,"error_code":"RATE_LIMITED","user_message":"慢点","trace_id":"t","retry_after":10,"details":{}}"#.data(using: .utf8)!
        let (client, _) = makeClient(429, body)
        do {
            _ = try await client.createSession(positionRoundId: "pr-1", companion: .qinglan)
            XCTFail("expected throw")
        } catch let e as APIError {
            XCTAssertEqual(e.errorCode, "RATE_LIMITED")
            XCTAssertEqual(e.retryAfter, 10)
        }
    }

    private func authTokenResponseBody() -> Data {
        """
        {"token_type":"bearer","access_token":"access-token","refresh_token":"refresh-token",
         "expires_in_seconds":900,
         "user":{"id":"user-1","phone_masked":"138****5678",
         "profile":{"display_name":null,"timezone":"Asia/Shanghai",
         "preferred_companion":"qinglan","target_summary":null,
         "weakness_summary":null,"memory_updated_at":null}}}
        """.data(using: .utf8)!
    }

    private func jwt(payload: String) -> String {
        "header.\(base64URL(payload)).signature"
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
