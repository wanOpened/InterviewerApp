import Foundation
import XCTest
@testable import InterviewerApp

@MainActor
final class HomeVoicePanelModelTests: XCTestCase {
    final class FakeAPI: APIClienting {
        private(set) var joinHomeVoiceCalls = 0
        var joinHomeVoiceError: Error?

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
            JoinResponse(livekit_room: "interview-room", livekit_token: "interview-token")
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
            throw TransportError(message: "not used")
        }
        func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
            PositionRead(id: positionId, title: "产品经理", company: "字节")
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
        func joinHomeVoice() async throws -> HomeVoiceJoinResponse {
            joinHomeVoiceCalls += 1
            if let joinHomeVoiceError {
                throw joinHomeVoiceError
            }
            return HomeVoiceJoinResponse(
                session_id: "home-session-1",
                livekit_room: "home-voice-home-session-1",
                livekit_token: "home-token",
                current_context: Self.homeContext()
            )
        }

        private static func homeContext() -> AgentHomeRead {
            AgentHomeRead(
                generated_at: "2026-06-08T12:00:00Z",
                primary_action: AgentHomePrimaryAction(
                    type: "create_schedule",
                    title: "创建日程",
                    spoken_prompt: "说出你想什么时候练。",
                    reason: "先把目标变成明确日程。",
                    cta: "创建",
                    target: [:]
                ),
                signals: [],
                voice_suggestions: [],
                briefing_items: nil
            )
        }
    }

    final class FakeLiveKit: LiveKitControlling {
        private(set) var connectCalls: [(url: String, token: String)] = []
        private(set) var microphoneStates: [Bool] = []
        private(set) var activateHomeVoiceCalls = 0
        private(set) var disconnectCount = 0
        private var onSessionEvent: ((HomeVoiceSessionEvent) -> Void)?
        private var onNavigateInterview: ((Data) -> Void)?
        private var onNavigateHomeAction: ((Data) -> Void)?
        private var onAudioRecoveryFailed: ((String) -> Void)?
        var localIdentity = "candidate"

        func connect(
            url: String,
            token: String,
            onSegment: @escaping (String, String, String, Bool) -> Void,
            onParticipantAttributes: @escaping (String, [String: String]) -> Void,
            onCaptionChunk: @escaping (String, String, String) -> Void,
            onState: @escaping (Bool) -> Void,
            onAudioRecoveryFailed: @escaping (String) -> Void
        ) async throws {
            connectCalls.append((url, token))
            microphoneStates.append(true)
            onState(true)
        }

        func connectHomeVoice(
            url: String,
            token: String,
            onSessionEvent: @escaping (HomeVoiceSessionEvent) -> Void,
            onNavigateInterview: @escaping (Data) -> Void,
            onNavigateHomeAction: @escaping (Data) -> Void,
            onState: @escaping (Bool) -> Void,
            onAudioRecoveryFailed: @escaping (String) -> Void
        ) async throws {
            connectCalls.append((url, token))
            self.onSessionEvent = onSessionEvent
            self.onNavigateInterview = onNavigateInterview
            self.onNavigateHomeAction = onNavigateHomeAction
            self.onAudioRecoveryFailed = onAudioRecoveryFailed
            onState(true)
        }

        func activateHomeVoice() async throws {
            activateHomeVoiceCalls += 1
        }

        func setMicrophone(enabled: Bool) async throws {
            microphoneStates.append(enabled)
        }

        func disconnect() async {
            disconnectCount += 1
        }

        func emit(_ event: HomeVoiceSessionEvent) {
            onSessionEvent?(event)
        }

        func emitNavigateInterview(_ payload: Data) {
            onNavigateInterview?(payload)
        }

        func emitNavigateHomeAction(_ payload: Data) {
            onNavigateHomeAction?(payload)
        }

        func emitAudioRecoveryFailed(_ message: String) {
            onAudioRecoveryFailed?(message)
        }
    }

    func test_startJoinsHomeVoiceRoomAndMovesConnectingToSpeakingWhenReady() async {
        let api = FakeAPI()
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: api,
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )

        await model.start()

        XCTAssertEqual(api.joinHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.connectCalls.first?.url, "ws://localhost:7880")
        XCTAssertEqual(liveKit.connectCalls.first?.token, "home-token")
        XCTAssertEqual(liveKit.activateHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.microphoneStates, [true])
        XCTAssertEqual(model.state, .speaking)
        XCTAssertEqual(model.qinglanState, .speaking)
        XCTAssertEqual(model.join?.livekit_room, "home-voice-home-session-1")
        XCTAssertEqual(model.currentContext?.primary_action.type, "create_schedule")
    }

    func test_prepareJoinsHomeVoiceRoomWithoutOpeningInlineInteractionOrMicrophone() async {
        let api = FakeAPI()
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: api,
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )

        await model.prepare()

        XCTAssertEqual(api.joinHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.connectCalls.first?.token, "home-token")
        XCTAssertEqual(liveKit.activateHomeVoiceCalls, 0)
        XCTAssertEqual(liveKit.microphoneStates, [])
        XCTAssertFalse(model.isInlineInteractionActive)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.qinglanState, .idle)
        XCTAssertEqual(model.currentContext?.primary_action.type, "create_schedule")

        model.apply(.connected)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.qinglanState, .idle)
    }

    func test_activatePreparedHomeVoiceSendsActivationAndEnablesMicrophone() async {
        let api = FakeAPI()
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: api,
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )

        await model.prepare()
        await model.activate()

        XCTAssertEqual(api.joinHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.connectCalls.count, 1)
        XCTAssertEqual(liveKit.activateHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.microphoneStates, [true])
        XCTAssertTrue(model.isInlineInteractionActive)
        XCTAssertEqual(model.state, .speaking)
    }

    func test_activateRetriesActivationPacketAfterInitialTap() async {
        let api = FakeAPI()
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: api,
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )

        await model.prepare()
        await model.activate()
        XCTAssertEqual(liveKit.activateHomeVoiceCalls, 1)
        XCTAssertEqual(liveKit.microphoneStates, [true])

        try? await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertGreaterThanOrEqual(liveKit.activateHomeVoiceCalls, 3)
        XCTAssertEqual(liveKit.microphoneStates, [true])

        await model.stop()
    }

    func test_sessionEventsDriveFiveStatesAndUserSpeechInterruptsSpeaking() {
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: FakeLiveKit(),
            liveKitURL: "ws://localhost:7880"
        )

        model.apply(.connected)
        XCTAssertEqual(model.state, .speaking)

        model.apply(.agentSpeakingChanged(true))
        XCTAssertEqual(model.state, .speaking)

        model.apply(.localSpeakingChanged(true))
        XCTAssertEqual(model.state, .listening)
        XCTAssertEqual(model.qinglanState, .listening)

        model.apply(.toolActivityChanged(true))
        XCTAssertEqual(model.state, .thinking)

        model.apply(.toolActivityChanged(false))
        XCTAssertEqual(model.state, .speaking)

        model.apply(.disconnected)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.qinglanState, .idle)
    }

    func test_qinglanAvatarStateProjectsSpeakingListeningAndThinkingFeedback() {
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: FakeLiveKit(),
            liveKitURL: "ws://localhost:7880"
        )

        model.apply(.agentSpeakingChanged(true))
        XCTAssertEqual(model.qinglanState, .speaking)

        model.apply(.localSpeakingChanged(true))
        XCTAssertEqual(model.qinglanState, .listening)

        model.apply(.toolActivityChanged(true))
        XCTAssertEqual(model.qinglanState, .thinking)

        model.apply(.toolActivityChanged(false))
        XCTAssertEqual(model.qinglanState, .speaking)
    }

    func test_transcriptionEventsKeepServerSpeechAndUserSpeechSeparate() {
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: FakeLiveKit(),
            liveKitURL: "ws://localhost:7880"
        )

        model.apply(.transcript(text: "帮我总结上一场", isFinal: false, speaker: .user))
        XCTAssertEqual(model.transcript, "帮我总结上一场")
        XCTAssertEqual(model.state, .listening)

        model.apply(.transcript(text: "上一场主要要补结构化表达。", isFinal: true, speaker: .agent))
        XCTAssertEqual(model.assistantMessage, "上一场主要要补结构化表达。")
        XCTAssertEqual(model.state, .speaking)
    }

    func test_navigateInterviewPayloadDecodeExtractsSessionID() throws {
        let payload = Data(#"{"session_id":"8F3A8C4A-0C58-4D8E-B8A5-8497A59D6211"}"#.utf8)

        let decoded = try HomeVoiceNavigateInterviewPayload.decode(payload)

        XCTAssertEqual(decoded.sessionId, "8F3A8C4A-0C58-4D8E-B8A5-8497A59D6211")
        XCTAssertThrowsError(try HomeVoiceNavigateInterviewPayload.decode(Data(#"{"sessionId":"missing"}"#.utf8)))
    }

    func test_navigateInterviewSignalRoutesAndTearsDownHomeVoiceSession() async {
        let liveKit = FakeLiveKit()
        var navigatedSessionIds: [String] = []
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880",
            onNavigateInterview: { navigatedSessionIds.append($0) }
        )
        await model.start()

        liveKit.emitNavigateInterview(Data(#"{"session_id":"session-for-interview"}"#.utf8))
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(navigatedSessionIds, ["session-for-interview"])
        XCTAssertEqual(liveKit.microphoneStates, [true, false])
        XCTAssertEqual(liveKit.disconnectCount, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.join)
    }

    func test_navigateResumeEditorSignalRoutesAndTearsDownHomeVoiceSession() async {
        let liveKit = FakeLiveKit()
        var routes: [HomeVoiceEditorRoute] = []
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880",
            onOpenEditor: { routes.append($0) }
        )
        await model.start()

        liveKit.emitNavigateHomeAction(
            Data(#"{"type":"open_resume_editor","route":"resume_editor","payload":{"schedule_id":"sch-1","position_id":"pos-1"}}"#.utf8)
        )
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(routes, [.resume(scheduleId: "sch-1", positionId: "pos-1")])
        XCTAssertEqual(liveKit.microphoneStates, [true, false])
        XCTAssertEqual(liveKit.disconnectCount, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.join)
    }

    func test_navigateJDEditorSignalRoutesAndTearsDownHomeVoiceSession() async {
        let liveKit = FakeLiveKit()
        var routes: [HomeVoiceEditorRoute] = []
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880",
            onOpenEditor: { routes.append($0) }
        )
        await model.start()

        liveKit.emitNavigateHomeAction(
            Data(#"{"type":"open_jd_editor","route":"jd_editor","payload":{"schedule_id":"sch-1","position_id":"pos-1"}}"#.utf8)
        )
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(routes, [.jd(scheduleId: "sch-1", positionId: "pos-1")])
        XCTAssertEqual(liveKit.microphoneStates, [true, false])
        XCTAssertEqual(liveKit.disconnectCount, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.join)
    }

    func test_navigateScheduleActionOpensScheduleListAndTearsDownHomeVoiceSession() async {
        let liveKit = FakeLiveKit()
        var scheduleListOpens = 0
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880",
            onOpenScheduleList: { scheduleListOpens += 1 }
        )
        await model.start()

        liveKit.emitNavigateHomeAction(
            Data(#"{"type":"create_schedule","route":"schedule","payload":{"schedule_id":"sch-9"}}"#.utf8)
        )
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(scheduleListOpens, 1)
        XCTAssertEqual(liveKit.microphoneStates, [true, false])
        XCTAssertEqual(liveKit.disconnectCount, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.join)
    }

    func test_navigateUnknownHomeActionIsIgnoredWithoutFakeConnectionError() async {
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )
        await model.start()

        liveKit.emitNavigateHomeAction(
            Data(#"{"type":"mystery","route":"nowhere","payload":{}}"#.utf8)
        )
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(liveKit.disconnectCount, 0)
    }

    func test_stopTearsDownRoomAndResetsToIdleWithoutClientWireEvents() async {
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )
        await model.start()

        await model.stop()

        XCTAssertEqual(liveKit.microphoneStates, [true, false])
        XCTAssertEqual(liveKit.disconnectCount, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.qinglanState, .idle)
        XCTAssertNil(model.join)
    }

    func test_audioRecoveryFailureReturnsToIdleWithErrorMessage() async {
        let liveKit = FakeLiveKit()
        let model = HomeVoicePanelModel(
            api: FakeAPI(),
            liveKit: liveKit,
            liveKitURL: "ws://localhost:7880"
        )

        await model.start()
        liveKit.emitAudioRecoveryFailed("音频恢复失败")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.errorMessage, "语音连接暂时不可用，请稍后再试。")
    }
}
