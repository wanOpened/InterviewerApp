import XCTest
@testable import InterviewerApp

@MainActor
final class ScheduleDetailModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var detail: ScheduleDetailRead
        private(set) var detailIDs: [String] = []
        private(set) var cancelledIDs: [String] = []
        private(set) var updateRequests: [(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?)] = []

        init(detail: ScheduleDetailRead) {
            self.detail = detail
        }

        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func createResume(rawText: String) async throws -> ResumeRead {
            ResumeRead(id: "r-new", version: 4, is_current: true, raw_text: rawText, created_at: "2026-06-09T12:00:00Z")
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
            detailIDs.append(id)
            return detail
        }
        func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead {
            updateRequests.append((id, scheduledAt, timezone, durationMinutes))
            let updated = InterviewScheduleRead(
                id: id,
                position_round_id: detail.schedule.position_round_id,
                scheduled_at: scheduledAt ?? detail.schedule.scheduled_at,
                timezone: timezone ?? detail.schedule.timezone,
                duration_minutes: durationMinutes ?? detail.schedule.duration_minutes,
                status: "scheduled",
                session_id: detail.schedule.session_id,
                raw_command: detail.schedule.raw_command,
                created_at: detail.schedule.created_at,
                position_title: detail.schedule.position_title,
                company: detail.schedule.company,
                round_name: detail.schedule.round_name
            )
            detail = ScheduleDetailRead(schedule: updated, position: detail.position, round: detail.round, resume: detail.resume)
            return updated
        }
        func cancelSchedule(id: String) async throws -> InterviewScheduleRead {
            cancelledIDs.append(id)
            let cancelled = InterviewScheduleRead(
                id: id,
                position_round_id: detail.schedule.position_round_id,
                scheduled_at: detail.schedule.scheduled_at,
                timezone: detail.schedule.timezone,
                duration_minutes: detail.schedule.duration_minutes,
                status: "cancelled",
                session_id: nil,
                raw_command: detail.schedule.raw_command,
                created_at: detail.schedule.created_at,
                position_title: detail.schedule.position_title,
                company: detail.schedule.company,
                round_name: detail.schedule.round_name
            )
            detail = ScheduleDetailRead(schedule: cancelled, position: detail.position, round: detail.round, resume: detail.resume)
            return cancelled
        }
        func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead {
            throw TransportError(message: "not used")
        }
        func agentHome() async throws -> AgentHomeRead {
            throw TransportError(message: "not used")
        }
        func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
            PositionRead(id: positionId, title: detail.position.title, company: detail.position.company, jd_text: jdText, created_at: detail.position.created_at)
        }
    }

    func test_refreshLoadsScheduleDetailOnce() async {
        let api = FakeAPI(detail: .fixture())
        let model = ScheduleDetailModel(scheduleId: "sch-1", api: api)

        await model.refresh()

        XCTAssertEqual(api.detailIDs, ["sch-1"])
        XCTAssertEqual(model.detail?.position.jd_text, "负责 AI 搜索产品。")
        XCTAssertEqual(model.headerTitle, "字节 · 终面")
    }

    func test_resumeReadinessShowsReadyRecentResumeAndSuggestsOldResume() async {
        let now = try! XCTUnwrap(ScheduleDateFormatter.date(from: "2026-06-09T12:00:00+08:00"))
        let recent = ScheduleDetailModel(scheduleId: "sch-1", api: FakeAPI(detail: .fixture(resumeCreatedAt: "2026-06-01T12:00:00+08:00")), now: { now })
        await recent.refresh()

        XCTAssertEqual(recent.resumeReadiness.label, "v3 · 已就绪")
        XCTAssertEqual(recent.resumeReadiness.kind, .ready)

        let old = ScheduleDetailModel(scheduleId: "sch-1", api: FakeAPI(detail: .fixture(resumeCreatedAt: "2026-04-01T12:00:00+08:00")), now: { now })
        await old.refresh()

        XCTAssertEqual(old.resumeReadiness.label, "v3 · 建议更新")
        XCTAssertEqual(old.resumeReadiness.kind, .suggestUpdate)
    }

    func test_resumeReadinessShowsMissingWhenDetailHasNoResume() async {
        let model = ScheduleDetailModel(scheduleId: "sch-1", api: FakeAPI(detail: .fixture(resume: nil)))

        await model.refresh()

        XCTAssertEqual(model.resumeReadiness.label, "未上传 · 去补充")
        XCTAssertEqual(model.resumeReadiness.kind, .missing)
    }

    func test_cancelScheduleCallsAPIAndUpdatesDetailStatus() async {
        let api = FakeAPI(detail: .fixture())
        let model = ScheduleDetailModel(scheduleId: "sch-1", api: api)
        await model.refresh()

        await model.cancel()

        XCTAssertEqual(api.cancelledIDs, ["sch-1"])
        XCTAssertEqual(model.detail?.schedule.status, "cancelled")
    }

    func test_rescheduleOneDayLaterCallsUpdateSchedule() async {
        let api = FakeAPI(detail: .fixture())
        let model = ScheduleDetailModel(scheduleId: "sch-1", api: api)
        await model.refresh()

        await model.rescheduleOneDayLater()

        XCTAssertEqual(api.updateRequests.count, 1)
        XCTAssertEqual(api.updateRequests.first?.id, "sch-1")
        XCTAssertEqual(api.updateRequests.first?.scheduledAt, "2026-06-11T15:00:00+08:00")
        XCTAssertEqual(api.updateRequests.first?.timezone, "Asia/Shanghai")
        XCTAssertEqual(api.updateRequests.first?.durationMinutes, 45)
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
        ),
        resumeCreatedAt: String? = nil
    ) -> ScheduleDetailRead {
        let resolvedResume: ResumeRead?
        if let resumeCreatedAt {
            resolvedResume = ResumeRead(
                id: "res-1",
                version: 3,
                is_current: true,
                raw_text: "候选人简历正文",
                created_at: resumeCreatedAt
            )
        } else {
            resolvedResume = resume
        }

        return ScheduleDetailRead(
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
            resume: resolvedResume
        )
    }
}
