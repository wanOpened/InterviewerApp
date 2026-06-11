import Foundation

protocol AgentHomeSpeechClienting {
    func agentHomeSpeech(text: String, companion: Companion) async throws -> Data
}

protocol APIClienting {
    func ensureUser() async throws
    func ensureResume() async throws
    func createResume(rawText: String) async throws -> ResumeRead
    func getCurrentResume() async throws -> ResumeRead
    func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead
    func getSession(id: String) async throws -> SessionRead
    func endSession(id: String) async throws -> SessionRead
    func sessionResults(id: String) async throws -> SessionResultRead
    func join(sessionId: String) async throws -> JoinResponse
    func joinHomeVoice() async throws -> HomeVoiceJoinResponse
    func parseScheduleDraft(rawInput: String, timezone: String) async throws -> ScheduleDraftRead
    func updateScheduleDraft(id: String, rawInput: String, timezone: String) async throws -> ScheduleDraftRead
    func confirmScheduleDraft(id: String) async throws -> InterviewScheduleRead
    func upcomingSchedules() async throws -> [InterviewScheduleRead]
    func scheduleDetail(id: String) async throws -> ScheduleDetailRead
    func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead
    func cancelSchedule(id: String) async throws -> InterviewScheduleRead
    func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead
    func agentHome() async throws -> AgentHomeRead
    func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead
}

extension APIClienting {
    func joinHomeVoice() async throws -> HomeVoiceJoinResponse {
        throw TransportError(message: "home voice join is not implemented by this client")
    }

    func getCurrentResume() async throws -> ResumeRead {
        throw TransportError(message: "current resume is not implemented by this client")
    }

    func scheduleDetail(id: String) async throws -> ScheduleDetailRead {
        throw TransportError(message: "schedule detail is not implemented by this client")
    }
}

final class APIClient: APIClienting, AgentHomeSpeechClienting {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let userExternalId: String
    private let transport: Transport

    init(baseURL: URL, userExternalId: String, transport: Transport? = nil) {
        self.baseURL = baseURL
        self.userExternalId = userExternalId
        self.transport = transport ?? { request in
            let (data, resp) = try await URLSession.shared.data(for: request)
            return (data, resp as! HTTPURLResponse)
        }
    }

    // MARK: request plumbing

    private func request(_ method: String, _ path: String,
                         body: Encodable? = nil,
                         extraHeaders: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(userExternalId, forHTTPHeaderField: "X-User-Id")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try? JSONEncoder().encode(AnyEncodable(body)) }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await transport(req)
        guard (200..<300).contains(resp.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw apiErr }
            throw TransportError(message: "HTTP \(resp.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendNoContent(_ req: URLRequest) async throws {
        let (data, resp) = try await transport(req)
        guard (200..<300).contains(resp.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw apiErr }
            throw TransportError(message: "HTTP \(resp.statusCode)")
        }
    }

    private func sendData(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await transport(req)
        guard (200..<300).contains(resp.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw apiErr }
            throw TransportError(message: "HTTP \(resp.statusCode)")
        }
        return data
    }

    // MARK: API surface (see docs/api/CLIENT_INTEGRATION.md §4)

    func ensureUser() async throws {
        let req = request("POST", "/v1/dev/users", body: DevUserRequest(external_id: userExternalId))
        _ = try await send(req, as: DevUserResponse.self)
    }

    func ensureResume() async throws {
        let getReq = request("GET", "/v1/resumes/me")
        let (data, resp) = try await transport(getReq)
        if resp.statusCode == 200, (try? JSONDecoder().decode(ResumeRead.self, from: data)) != nil {
            return
        }
        if resp.statusCode == 404 {
            throw ResumeRequiredError()
        }
        if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) {
            throw apiErr
        }
        throw TransportError(message: "HTTP \(resp.statusCode)")
    }

    func getCurrentResume() async throws -> ResumeRead {
        try await send(request("GET", "/v1/resumes/me"), as: ResumeRead.self)
    }

    func createResume(rawText: String) async throws -> ResumeRead {
        let req = request(
            "POST",
            "/v1/resumes",
            body: ResumeCreateRequest(raw_text: rawText)
        )
        return try await send(req, as: ResumeRead.self)
    }

    func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead {
        let req = request("POST", "/v1/sessions",
            body: SessionCreateRequest(position_round_id: positionRoundId, companion: companion),
            extraHeaders: ["Idempotency-Key": UUID().uuidString])
        return try await send(req, as: SessionRead.self)
    }

    func getSession(id: String) async throws -> SessionRead {
        try await send(request("GET", "/v1/sessions/\(id)"), as: SessionRead.self)
    }

    func endSession(id: String) async throws -> SessionRead {
        try await send(request("POST", "/v1/sessions/\(id)/end"), as: SessionRead.self)
    }

    func sessionResults(id: String) async throws -> SessionResultRead {
        try await send(request("GET", "/v1/sessions/\(id)/results"), as: SessionResultRead.self)
    }

    func join(sessionId: String) async throws -> JoinResponse {
        try await send(request("POST", "/v1/sessions/\(sessionId)/join"), as: JoinResponse.self)
    }

    func joinHomeVoice() async throws -> HomeVoiceJoinResponse {
        try await send(request("POST", "/v1/home-voice/join"), as: HomeVoiceJoinResponse.self)
    }

    func parseScheduleDraft(rawInput: String, timezone: String) async throws -> ScheduleDraftRead {
        let req = request(
            "POST",
            "/v1/schedule-drafts/parse",
            body: ScheduleDraftParseRequest(text: rawInput, timezone: timezone)
        )
        return try await send(req, as: ScheduleDraftRead.self)
    }

    func updateScheduleDraft(id: String, rawInput: String, timezone: String) async throws -> ScheduleDraftRead {
        let req = request(
            "PATCH",
            "/v1/schedule-drafts/\(id)",
            body: ScheduleDraftParseRequest(text: rawInput, timezone: timezone)
        )
        return try await send(req, as: ScheduleDraftRead.self)
    }

    func confirmScheduleDraft(id: String) async throws -> InterviewScheduleRead {
        try await send(
            request("POST", "/v1/schedule-drafts/\(id)/confirm"),
            as: InterviewScheduleRead.self
        )
    }

    func upcomingSchedules() async throws -> [InterviewScheduleRead] {
        let list = try await send(
            request("GET", "/v1/interview-schedules/upcoming"),
            as: InterviewScheduleList.self
        )
        return list.schedules
    }

    func scheduleDetail(id: String) async throws -> ScheduleDetailRead {
        try await send(
            request("GET", "/v1/interview-schedules/\(id)"),
            as: ScheduleDetailRead.self
        )
    }

    func updateSchedule(
        id: String,
        scheduledAt: String?,
        timezone: String?,
        durationMinutes: Int?
    ) async throws -> InterviewScheduleRead {
        try await send(
            request(
                "PATCH",
                "/v1/interview-schedules/\(id)",
                body: InterviewScheduleUpdateRequest(
                    scheduled_at: scheduledAt,
                    timezone: timezone,
                    duration_minutes: durationMinutes
                )
            ),
            as: InterviewScheduleRead.self
        )
    }

    func cancelSchedule(id: String) async throws -> InterviewScheduleRead {
        try await send(
            request("POST", "/v1/interview-schedules/\(id)/cancel"),
            as: InterviewScheduleRead.self
        )
    }

    func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead {
        try await send(
            request(
                "POST",
                "/v1/interview-schedules/\(id)/start",
                body: ScheduleStartRequest(companion: companion)
            ),
            as: ScheduleStartRead.self
        )
    }

    func agentHome() async throws -> AgentHomeRead {
        try await send(request("GET", "/v1/agent-home"), as: AgentHomeRead.self)
    }

    func agentHomeSpeech(text: String, companion: Companion) async throws -> Data {
        try await sendData(
            request(
                "POST",
                "/v1/agent-home/speech",
                body: AgentHomeSpeechRequest(text: text, companion: companion),
                extraHeaders: ["Accept": "audio/wav"]
            )
        )
    }

    func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
        try await send(
            request(
                "PATCH",
                "/v1/positions/\(positionId)/jd",
                body: PositionJdUpdateRequest(jd_text: jdText)
            ),
            as: PositionRead.self
        )
    }
}

/// Type-erasing wrapper so `request(body:)` can take any Encodable.
private struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
