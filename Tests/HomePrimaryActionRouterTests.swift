import XCTest
@testable import InterviewerApp

final class HomePrimaryActionRouterTests: XCTestCase {
    func test_interviewClassActionsRouteToInterviewLaunch() {
        XCTAssertEqual(
            HomePrimaryActionRouter.route(for: action(type: "resume_live_session", target: ["session_id": "s-1"])),
            .interview(.resume(sessionId: "s-1"))
        )
        XCTAssertEqual(
            HomePrimaryActionRouter.route(for: action(type: "start_practice", target: ["schedule_id": "sch-1"])),
            .interview(.startSchedule(scheduleId: "sch-1"))
        )
        XCTAssertEqual(
            HomePrimaryActionRouter.route(for: action(type: "practice_weakness", target: ["position_round_id": "round-1"])),
            .interview(.startRound(positionRoundId: "round-1"))
        )
        XCTAssertEqual(
            HomePrimaryActionRouter.route(for: action(type: "quick_start", target: ["position_round_id": "round-2"])),
            .interview(.startRound(positionRoundId: "round-2"))
        )
    }

    func test_conversationClassActionsRouteToVoiceSession() {
        for type in ["create_schedule", "create_target", "add_jd", "review_result", "wait_scoring"] {
            XCTAssertEqual(HomePrimaryActionRouter.route(for: action(type: type)), .voice)
        }
    }

    func test_interviewClassActionWithoutUsableTargetFallsBackToVoice() {
        XCTAssertEqual(HomePrimaryActionRouter.route(for: action(type: "start_practice")), .voice)
        XCTAssertEqual(HomePrimaryActionRouter.route(for: action(type: "resume_live_session")), .voice)
        XCTAssertEqual(HomePrimaryActionRouter.route(for: action(type: "quick_start")), .voice)
    }

    func test_primaryActionPresentationIsNilWhenActionIsNil() {
        XCTAssertNil(HomePrimaryActionPresentation.make(action: nil, nextScheduleID: "sch-1"))
    }

    func test_primaryActionPresentationSuppressesSameScheduleAsPeek() {
        XCTAssertNil(
            HomePrimaryActionPresentation.make(
                action: action(type: "start_practice", target: ["schedule_id": "sch-1"]),
                nextScheduleID: "sch-1"
            )
        )
    }

    func test_primaryActionPresentationSuppressesPrepareDuplicateWithoutComparableID() {
        XCTAssertNil(
            HomePrimaryActionPresentation.make(
                action: action(type: "start_practice", title: "准备明天的终面", cta: "去准备"),
                nextScheduleID: "sch-1"
            )
        )
    }

    func test_primaryActionPresentationRendersNonDuplicateActions() {
        XCTAssertEqual(
            HomePrimaryActionPresentation.make(
                action: action(type: "review_result", title: "查看新报告", cta: "查看"),
                nextScheduleID: "sch-1"
            ),
            HomePrimaryActionPresentation(title: "查看新报告", accessory: "chevron.right")
        )

        XCTAssertEqual(
            HomePrimaryActionPresentation.make(
                action: action(type: "start_practice", title: "开始练习", cta: "开始", target: ["schedule_id": "sch-2"]),
                nextScheduleID: "sch-1"
            ),
            HomePrimaryActionPresentation(title: "开始练习", accessory: "chevron.right")
        )
    }

    private func action(
        type: String,
        title: String = "下一步",
        cta: String = "开始",
        target: [String: String] = [:]
    ) -> AgentHomePrimaryAction {
        AgentHomePrimaryAction(
            type: type,
            title: title,
            spoken_prompt: "继续",
            reason: "当前最重要",
            cta: cta,
            target: target
        )
    }
}
