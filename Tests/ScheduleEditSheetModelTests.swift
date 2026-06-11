import XCTest
@testable import InterviewerApp

@MainActor
final class ScheduleEditSheetModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var currentResume = ResumeRead(
            id: "r-current",
            version: 2,
            is_current: true,
            raw_text: "当前简历正文",
            created_at: "2026-06-01T12:00:00Z"
        )
        private(set) var getCurrentResumeCalls = 0
        private(set) var updatedJD: (positionId: String, jdText: String)?
        private(set) var createdResumeText: String?

        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func getCurrentResume() async throws -> ResumeRead {
            getCurrentResumeCalls += 1
            return currentResume
        }
        func createResume(rawText: String) async throws -> ResumeRead {
            createdResumeText = rawText
            return ResumeRead(id: "r-new", version: 3, is_current: true, raw_text: rawText, created_at: "2026-06-09T12:00:00Z")
        }
        func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead {
            SessionRead(id: "s-1", status: "created", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func getSession(id: String) async throws -> SessionRead {
            SessionRead(id: id, status: "ready", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func endSession(id: String) async throws -> SessionRead {
            SessionRead(id: id, status: "ended", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func sessionResults(id: String) async throws -> SessionResultRead {
            SessionResultRead(session_id: id, overall_score: 80, dimension_scores: [:], per_question_review: [], coaching_plan: [:], is_partial: false)
        }
        func join(sessionId: String) async throws -> JoinResponse {
            JoinResponse(livekit_room: "room", livekit_token: "token")
        }
        func parseScheduleDraft(rawInput: String, timezone: String) async throws -> ScheduleDraftRead {
            throw TransportError(message: "not used")
        }
        func updateScheduleDraft(id: String, rawInput: String, timezone: String) async throws -> ScheduleDraftRead {
            throw TransportError(message: "not used")
        }
        func confirmScheduleDraft(id: String) async throws -> InterviewScheduleRead {
            throw TransportError(message: "not used")
        }
        func upcomingSchedules() async throws -> [InterviewScheduleRead] { [] }
        func scheduleDetail(id: String) async throws -> ScheduleDetailRead {
            throw TransportError(message: "not used")
        }
        func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead {
            throw TransportError(message: "not used")
        }
        func cancelSchedule(id: String) async throws -> InterviewScheduleRead {
            throw TransportError(message: "not used")
        }
        func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead {
            throw TransportError(message: "not used")
        }
        func agentHome() async throws -> AgentHomeRead {
            throw TransportError(message: "not used")
        }
        func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
            updatedJD = (positionId, jdText)
            return PositionRead(id: positionId, title: "产品经理", company: "字节", jd_text: jdText, created_at: "2026-06-01T12:00:00Z")
        }
    }

    func test_jdEditorSavesThroughUpdatePositionJD() async {
        let api = FakeAPI()
        let model = ScheduleEditSheetModel(kind: .jd, detail: .fixture(), api: api)

        await model.loadInitialText()
        model.text = "负责 AI 搜索增长与知识库体验。"
        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(api.updatedJD?.positionId, "p-1")
        XCTAssertEqual(api.updatedJD?.jdText, "负责 AI 搜索增长与知识库体验。")
    }

    func test_resumeEditorLoadsCurrentResumeWhenDetailResumeIsMissing() async {
        let api = FakeAPI()
        let model = ScheduleEditSheetModel(kind: .resume, detail: .fixture(resume: nil), api: api)

        await model.loadInitialText()

        XCTAssertEqual(api.getCurrentResumeCalls, 1)
        XCTAssertEqual(model.text, "当前简历正文")
    }

    func test_resumeEditorSavesThroughCreateResume() async {
        let api = FakeAPI()
        let model = ScheduleEditSheetModel(kind: .resume, detail: .fixture(), api: api)

        await model.loadInitialText()
        model.text = "更新后的简历正文"
        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(api.createdResumeText, "更新后的简历正文")
    }
}

private extension ScheduleDetailRead {
    static func fixture(
        resume: ResumeRead? = ResumeRead(
            id: "res-1",
            version: 3,
            is_current: true,
            raw_text: "候选人简历正文",
            created_at: "2026-06-01T12:00:00+08:00"
        )
    ) -> ScheduleDetailRead {
        ScheduleDetailRead(
            schedule: InterviewScheduleRead(
                id: "sch-1",
                position_round_id: "pr-1",
                scheduled_at: "2026-06-10T15:00:00+08:00",
                timezone: "Asia/Shanghai",
                duration_minutes: 45,
                status: "scheduled",
                session_id: nil,
                raw_command: "下周二字节终面",
                created_at: "2026-06-09T12:00:00Z",
                position_title: "产品经理",
                company: "字节",
                round_name: "终面"
            ),
            position: PositionRead(
                id: "p-1",
                title: "产品经理",
                company: "字节",
                jd_text: "负责 AI 搜索产品。",
                seniority: "senior",
                created_at: "2026-06-01T12:00:00Z"
            ),
            round: RoundRead(id: "round-1", round_name: "终面"),
            resume: resume
        )
    }
}
