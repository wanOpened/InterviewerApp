import XCTest
@testable import InterviewerApp

@MainActor
final class ScheduleListModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var schedules: [InterviewScheduleRead] = []
        private(set) var upcomingCalls = 0

        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func createResume(rawText: String) async throws -> ResumeRead {
            ResumeRead(id: "r-1", version: 1, is_current: true, raw_text: rawText, created_at: "2026-06-09T12:00:00Z")
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
        func upcomingSchedules() async throws -> [InterviewScheduleRead] {
            upcomingCalls += 1
            return schedules
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
            PositionRead(id: positionId, title: "产品经理", company: "字节", jd_text: jdText, created_at: "2026-06-09T12:00:00Z")
        }
    }

    func test_refreshLoadsUpcomingSchedulesSortedByClosestTime() async {
        let api = FakeAPI()
        api.schedules = [
            .fixture(id: "later", scheduledAt: "2026-06-13T15:00:00+08:00"),
            .fixture(id: "soon", scheduledAt: "2026-06-10T15:00:00+08:00"),
        ]
        let model = ScheduleListModel(api: api)

        await model.refresh()

        XCTAssertEqual(api.upcomingCalls, 1)
        XCTAssertEqual(model.recentSchedules.map(\.id), ["soon", "later"])
    }

    func test_statusDisplayMapsScheduleStatesToPlanLabels() {
        XCTAssertEqual(ScheduleStatusDisplay(status: "scheduled").label, "待开始")
        XCTAssertEqual(ScheduleStatusDisplay(status: "preparing").label, "待开始")
        XCTAssertEqual(ScheduleStatusDisplay(status: "in_progress").label, "进行中")
        XCTAssertEqual(ScheduleStatusDisplay(status: "ended").label, "已结束")
        XCTAssertEqual(ScheduleStatusDisplay(status: "cancelled").label, "已取消")
    }

    func test_countdownTextMatchesTodayTomorrowAndDayCount() throws {
        let now = try XCTUnwrap(ScheduleDateFormatter.date(from: "2026-06-09T10:00:00+08:00"))

        XCTAssertEqual(
            ScheduleDateFormatter.countdownText(for: "2026-06-09T14:00:00+08:00", now: now),
            "今天 14:00"
        )
        XCTAssertEqual(
            ScheduleDateFormatter.countdownText(for: "2026-06-10T14:00:00+08:00", now: now),
            "明天 14:00"
        )
        XCTAssertEqual(
            ScheduleDateFormatter.countdownText(for: "2026-06-12T14:00:00+08:00", now: now),
            "3 天"
        )
    }

    func test_displayTitleUsesCompanyAndRoundNameFromScheduleFields() {
        let schedule = InterviewScheduleRead.fixture(
            id: "sch-1",
            company: "字节",
            roundName: "终面"
        )

        XCTAssertEqual(ScheduleListDisplay(schedule: schedule).title, "字节 · 终面")
    }
}

private extension InterviewScheduleRead {
    static func fixture(
        id: String = "sch-1",
        scheduledAt: String = "2026-06-10T15:00:00+08:00",
        status: String = "scheduled",
        company: String? = "字节",
        positionTitle: String? = "产品经理",
        roundName: String? = "终面"
    ) -> InterviewScheduleRead {
        InterviewScheduleRead(
            id: id,
            position_round_id: "pr-\(id)",
            scheduled_at: scheduledAt,
            timezone: "Asia/Shanghai",
            duration_minutes: 45,
            status: status,
            session_id: nil,
            raw_command: "下周二字节终面",
            created_at: "2026-06-09T12:00:00Z",
            position_title: positionTitle,
            company: company,
            round_name: roundName
        )
    }
}
