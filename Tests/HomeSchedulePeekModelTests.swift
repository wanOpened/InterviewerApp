import XCTest
@testable import InterviewerApp

@MainActor
final class HomeSchedulePeekModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var schedules: [InterviewScheduleRead] = []
        var upcomingError: Error?
        private(set) var upcomingCalls = 0
        private(set) var cancelledIDs: [String] = []

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
            if let upcomingError {
                throw upcomingError
            }
            return schedules
        }
        func scheduleDetail(id: String) async throws -> ScheduleDetailRead {
            throw TransportError(message: "not used")
        }
        func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead {
            throw TransportError(message: "not used")
        }
        func cancelSchedule(id: String) async throws -> InterviewScheduleRead {
            cancelledIDs.append(id)
            return .fixture(id: id, status: "cancelled")
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

    func test_entryStateShowsNextScheduleWhenUpcomingSchedulesExist() async {
        let api = FakeAPI()
        api.schedules = [
            .fixture(id: "sch-1", scheduledAt: "2026-06-12T15:00:00+08:00"),
            .fixture(id: "sch-2", scheduledAt: "2026-06-13T15:00:00+08:00"),
        ]
        let model = HomeSchedulePeekModel(api: api)

        await model.refresh()

        XCTAssertEqual(api.upcomingCalls, 1)
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.upcomingCount, 2)
        switch model.entryState {
        case .nextSchedule(let label, let secondaryLabel):
            XCTAssertEqual(label, "明天 15:00 · 字节终面")
            XCTAssertNil(secondaryLabel)
        case .empty:
            XCTFail("Expected a next schedule entry state.")
        }
    }

    func test_entryStateIsEmptyAndVisibleWhenNoUpcomingSchedulesExist() async {
        let model = HomeSchedulePeekModel(api: FakeAPI())

        await model.refresh()

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.upcomingCount, 0)
        XCTAssertEqual(model.entryState, .empty)
        XCTAssertEqual(model.label, "暂无安排")
        XCTAssertNil(model.secondaryLabel)
    }

    func test_entryStateIsEmptyAndVisibleWhenRefreshFails() async {
        let api = FakeAPI()
        api.upcomingError = TransportError(message: "network down")
        let model = HomeSchedulePeekModel(api: api)

        await model.refresh()

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.upcomingCount, 0)
        XCTAssertEqual(model.entryState, .empty)
        XCTAssertEqual(model.label, "暂无安排")
        XCTAssertNil(model.secondaryLabel)
    }

    func test_detectsNewScheduleAfterVoiceSnapshotAndBuildsConfirmation() async {
        let api = FakeAPI()
        api.schedules = [.fixture(id: "old")]
        let model = HomeSchedulePeekModel(api: api)
        await model.refresh()
        model.captureCreationSnapshot()

        api.schedules = [
            .fixture(id: "old"),
            .fixture(id: "new", scheduledAt: "2026-06-10T15:00:00+08:00", company: "字节", roundName: "终面"),
        ]
        await model.refreshAfterVoiceActivity()

        XCTAssertEqual(model.creationConfirmation?.scheduleID, "new")
        XCTAssertEqual(model.creationConfirmation?.summary, "周三 15:00 · 字节 · 终面")
    }

    func test_doesNotShowConfirmationWhenVoiceDiffHasNoNewSchedule() async {
        let api = FakeAPI()
        api.schedules = [.fixture(id: "old")]
        let model = HomeSchedulePeekModel(api: api)
        await model.refresh()
        model.captureCreationSnapshot()

        await model.refreshAfterVoiceActivity()

        XCTAssertNil(model.creationConfirmation)
    }

    func test_cancelCreationConfirmationCallsCancelScheduleAndDismissesCard() async {
        let api = FakeAPI()
        api.schedules = [.fixture(id: "new")]
        let model = HomeSchedulePeekModel(api: api)
        model.captureCreationSnapshot()
        await model.refreshAfterVoiceActivity()

        await model.cancelCreationConfirmation()

        XCTAssertEqual(api.cancelledIDs, ["new"])
        XCTAssertNil(model.creationConfirmation)
    }
}

private extension InterviewScheduleRead {
    static func fixture(
        id: String,
        scheduledAt: String = "2026-06-10T15:00:00+08:00",
        status: String = "scheduled",
        company: String? = "字节",
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
            position_title: "产品经理",
            company: company,
            round_name: roundName
        )
    }
}
