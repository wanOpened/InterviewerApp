import XCTest
@testable import InterviewerApp

@MainActor
final class AgentHomeModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var home: AgentHomeRead
        var agentHomeCalls = 0
        var updatedJD: (positionId: String, jdText: String)?

        init(home: AgentHomeRead) {
            self.home = home
        }

        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func createResume(rawText: String) async throws -> ResumeRead {
            ResumeRead(id: "r-1", version: 1, is_current: true)
        }
        func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead {
            SessionRead(id: "s-1", status: "created", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func getSession(id: String) async throws -> SessionRead {
            SessionRead(id: id, status: "ready", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func join(sessionId: String) async throws -> JoinResponse {
            JoinResponse(livekit_room: "r", livekit_token: "tok")
        }
        func endSession(id: String) async throws -> SessionRead {
            SessionRead(id: id, status: "ended", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func sessionResults(id: String) async throws -> SessionResultRead {
            SessionResultRead(
                session_id: id,
                overall_score: 82,
                dimension_scores: [:],
                per_question_review: [],
                coaching_plan: [:],
                is_partial: false
            )
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
        func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead {
            InterviewScheduleRead(
                id: id,
                position_round_id: "pr-1",
                scheduled_at: scheduledAt ?? "2026-06-03T15:00:00+08:00",
                timezone: timezone ?? "Asia/Shanghai",
                duration_minutes: durationMinutes ?? 30,
                status: "scheduled",
                session_id: nil,
                raw_command: "明天下午三点产品二面",
                created_at: "2026-06-02T18:00:00Z"
            )
        }
        func cancelSchedule(id: String) async throws -> InterviewScheduleRead {
            InterviewScheduleRead(
                id: id,
                position_round_id: "pr-1",
                scheduled_at: "2026-06-03T15:00:00+08:00",
                timezone: "Asia/Shanghai",
                duration_minutes: 30,
                status: "cancelled",
                session_id: nil,
                raw_command: "明天下午三点产品二面",
                created_at: "2026-06-02T18:00:00Z"
            )
        }
        func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead {
            throw TransportError(message: "not used")
        }
        func agentHome() async throws -> AgentHomeRead {
            agentHomeCalls += 1
            return home
        }
        func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
            updatedJD = (positionId, jdText)
            return PositionRead(id: positionId, title: "产品经理", company: "字节")
        }
    }

    func test_refreshLoadsRecommendationAndSetsQinglanSpeaking() async throws {
        let api = FakeAPI(home: .fixture(type: "start_practice", target: ["schedule_id": "sch-1"]))
        let model = AgentHomeModel(api: api)

        await model.refresh()

        XCTAssertEqual(api.agentHomeCalls, 1)
        XCTAssertEqual(model.recommendation?.primary_action.type, "start_practice")
        XCTAssertEqual(model.primaryTitle, "开始这场面试的针对练习")
        XCTAssertEqual(model.qinglanState, .speaking)
    }

    func test_finishSpeakingMovesQinglanToWaitingForUserReply() async throws {
        let api = FakeAPI(home: .fixture(type: "start_practice", target: ["schedule_id": "sch-1"]))
        let model = AgentHomeModel(api: api)

        model.beginSpeaking()
        model.finishSpeaking()

        XCTAssertEqual(model.qinglanState, .waiting)
    }

    func test_voiceFinishMethodsAreIdempotentTeardownGuards() async throws {
        let api = FakeAPI(home: .fixture(type: "start_practice", target: ["schedule_id": "sch-1"]))
        let model = AgentHomeModel(api: api)

        model.beginListening()
        model.finishListening()
        model.finishListening()

        XCTAssertNotEqual(model.qinglanState, .listening)

        model.beginSpeaking()
        model.finishSpeaking()
        model.finishSpeaking()

        XCTAssertNotEqual(model.qinglanState, .speaking)

        model.finishListening()
        XCTAssertNotEqual(model.qinglanState, .listening)
    }

    func test_lightweightItemsAlwaysIncludeQuickPracticeFallback() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-05T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "add_jd",
                title: "补 JD",
                spoken_prompt: "先把 JD 补上。",
                reason: "缺少岗位描述。",
                cta: "补 JD",
                target: ["position_id": "p-1", "position_round_id": "pr-1"]
            ),
            signals: [],
            voice_suggestions: [],
            briefing_items: nil
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        let quickPractice = model.lightweightItems.first {
            $0.actionType == AgentHomeActionType.quickStart.rawValue
        }
        XCTAssertEqual(quickPractice?.title, "快练 10 分钟")
        XCTAssertEqual(quickPractice?.target["position_round_id"], "pr-1")
        XCTAssertFalse(quickPractice?.emphasized ?? true)
    }

    func test_briefingNarrationUsesCurrentRecommendation() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-06T00:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "start_practice",
                title: "10分钟针对性训练",
                spoken_prompt: "明天下午面试，先练指标追问。",
                reason: "上次指标题偏弱。",
                cta: "开始",
                target: [:]
            ),
            signals: [],
            voice_suggestions: [],
            briefing_items: nil
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        XCTAssertEqual(
            model.briefingNarration,
            "明天下午面试，先练指标追问。10分钟针对性训练。上次指标题偏弱。"
        )
    }

    func test_updateJDRefreshesRecommendation() async throws {
        let api = FakeAPI(home: .fixture(type: "add_jd", target: ["position_id": "p-1"]))
        let model = AgentHomeModel(api: api)

        await model.refresh()
        await model.updateJD("负责企业 AI 搜索的可信回答和知识库体验。")

        XCTAssertEqual(api.updatedJD?.positionId, "p-1")
        XCTAssertEqual(api.agentHomeCalls, 2)
    }

    func test_briefingItemsMapsPrimaryActionAndSignalsToRankedFeed() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-03T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "start_practice",
                title: "还差一次针对性模拟",
                spoken_prompt: "先练最重要的一题。",
                reason: "上次指标追问偏弱。",
                cta: "去练这道题",
                target: ["position_round_id": "pr-1"]
            ),
            signals: [
                AgentHomeSignal(type: "result_ready", label: "复盘还没看，有 3 个重点", severity: "high"),
                AgentHomeSignal(type: "upcoming_interview", label: "周四 14:00 小红书 PM 二面", severity: "medium"),
            ],
            voice_suggestions: ["开始练习"],
            briefing_items: nil
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        XCTAssertEqual(
            model.briefingItems,
            [
                BriefingItem(
                    sourceTag: .interview,
                    title: "还差一次针对性模拟",
                    reason: "上次指标追问偏弱。",
                    cta: "去练这道题",
                    actionType: "start_practice",
                    target: ["position_round_id": "pr-1"],
                    emphasized: true
                ),
                BriefingItem(
                    sourceTag: .review,
                    title: "复盘还没看，有 3 个重点",
                    reason: "青岚建议优先关注",
                    cta: "查看",
                    actionType: "start_practice",
                    target: ["position_round_id": "pr-1"],
                    emphasized: false
                ),
                BriefingItem(
                    sourceTag: .schedule,
                    title: "周四 14:00 小红书 PM 二面",
                    reason: "值得提前准备",
                    cta: "准备",
                    actionType: "start_practice",
                    target: ["position_round_id": "pr-1"],
                    emphasized: false
                ),
            ]
        )
    }

    func test_briefingItemsUsesServerFeedAndEachItemsOwnRouteWhenPresent() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-03T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "start_practice",
                title: "旧主操作",
                spoken_prompt: "旧主操作提示",
                reason: "旧主操作原因",
                cta: "旧主操作 CTA",
                target: ["position_round_id": "primary-round"]
            ),
            signals: [
                AgentHomeSignal(type: "upcoming_interview", label: "旧信号", severity: "high")
            ],
            voice_suggestions: ["开始练习"],
            briefing_items: [
                AgentHomeBriefingItem(
                    source: "review",
                    action_type: "review_result",
                    target: ["session_id": "review-session"],
                    title: "复盘已生成",
                    reason: "先看三个关键反馈",
                    cta: "查看复盘",
                    emphasis: true
                ),
                AgentHomeBriefingItem(
                    source: "schedule",
                    action_type: "create_schedule",
                    target: ["position_round_id": "schedule-round"],
                    title: "安排下一轮",
                    reason: "周内还有空档",
                    cta: "创建日程",
                    emphasis: false
                ),
            ]
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        XCTAssertEqual(
            model.briefingItems,
            [
                BriefingItem(
                    sourceTag: .review,
                    title: "复盘已生成",
                    reason: "先看三个关键反馈",
                    cta: "查看复盘",
                    actionType: "review_result",
                    target: ["session_id": "review-session"],
                    emphasized: true
                ),
                BriefingItem(
                    sourceTag: .schedule,
                    title: "安排下一轮",
                    reason: "周内还有空档",
                    cta: "创建日程",
                    actionType: "create_schedule",
                    target: ["position_round_id": "schedule-round"],
                    emphasized: false
                ),
            ]
        )
    }

    func test_briefingItemsMapsQuickStartAsSecondarySelfRoutingItem() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-05T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "create_schedule",
                title: "给最近的目标安排一次练习",
                spoken_prompt: "告诉我哪天练哪一轮。",
                reason: "先把目标变成可执行日程。",
                cta: "创建日程",
                target: ["position_id": "primary-position"]
            ),
            signals: [],
            voice_suggestions: ["明天下午三点练二面"],
            briefing_items: [
                AgentHomeBriefingItem(
                    source: "schedule",
                    action_type: "create_schedule",
                    target: ["position_id": "primary-position"],
                    title: "给最近的目标安排一次练习",
                    reason: "先把目标变成可执行日程。",
                    cta: "创建日程",
                    emphasis: true
                ),
                AgentHomeBriefingItem(
                    source: "interview",
                    action_type: AgentHomeActionType.quickStart.rawValue,
                    target: [
                        "position_round_id": "quick-round",
                        "position_id": "quick-position",
                    ],
                    title: "直接开始一场面试",
                    reason: "不用等日程，有十分钟就能马上来一场针对练习。",
                    cta: "马上开始",
                    emphasis: false
                ),
            ]
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        let quickStart = model.briefingItems.first {
            $0.actionType == AgentHomeActionType.quickStart.rawValue
        }
        XCTAssertEqual(
            quickStart,
            BriefingItem(
                sourceTag: .interview,
                title: "直接开始一场面试",
                reason: "不用等日程，有十分钟就能马上来一场针对练习。",
                cta: "马上开始",
                actionType: AgentHomeActionType.quickStart.rawValue,
                target: [
                    "position_round_id": "quick-round",
                    "position_id": "quick-position",
                ],
                emphasized: false
            )
        )
        XCTAssertEqual(quickStart?.actionType, AgentHomeActionType.quickStart.rawValue)
        XCTAssertFalse(quickStart?.emphasized ?? true)
        XCTAssertNotEqual(quickStart?.target, home.primary_action.target)
    }

    func test_briefingItemsDoesNotDeriveFallbackWhenServerFeedIsPresentButEmpty() async {
        let home = AgentHomeRead(
            generated_at: "2026-06-03T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: "start_practice",
                title: "旧主操作",
                spoken_prompt: "旧主操作提示",
                reason: "旧主操作原因",
                cta: "旧主操作 CTA",
                target: ["position_round_id": "primary-round"]
            ),
            signals: [
                AgentHomeSignal(type: "upcoming_interview", label: "旧信号", severity: "high")
            ],
            voice_suggestions: ["开始练习"],
            briefing_items: []
        )
        let model = AgentHomeModel(api: FakeAPI(home: home))

        await model.refresh()

        XCTAssertEqual(model.briefingItems, [])
    }

    func test_briefingPrimarySourceTagMapsActionTypes() async {
        let expectations: [(String, SourceTag.Kind)] = [
            ("start_practice", .interview),
            ("practice_weakness", .interview),
            ("review_result", .review),
            ("wait_scoring", .review),
            ("create_schedule", .schedule),
            ("create_target", .schedule),
            ("add_jd", .schedule),
        ]

        for (actionType, expectedTag) in expectations {
            let model = AgentHomeModel(api: FakeAPI(home: .fixture(type: actionType, target: [:])))
            await model.refresh()
            XCTAssertEqual(model.briefingItems.first?.sourceTag, expectedTag)
        }
    }
}

private extension AgentHomeRead {
    static func fixture(type: String, target: [String: String]) -> AgentHomeRead {
        AgentHomeRead(
            generated_at: "2026-06-03T12:00:00Z",
            primary_action: AgentHomePrimaryAction(
                type: type,
                title: "开始这场面试的针对练习",
                spoken_prompt: "明天就要面试了，我们先做一轮针对练习。",
                reason: "临近面试且没有练习记录。",
                cta: "开始练习",
                target: target
            ),
            signals: [
                AgentHomeSignal(type: "upcoming_interview", label: "明天面试", severity: "high")
            ],
            voice_suggestions: ["开始练习"],
            briefing_items: nil
        )
    }
}
