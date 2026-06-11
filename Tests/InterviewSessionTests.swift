import XCTest
@testable import InterviewerApp

@MainActor
final class InterviewSessionTests: XCTestCase {
    final class Timeline {
        var events: [String] = []
    }

    final class FakeAPI: APIClienting {
        var statuses: [String]; var joined = false
        var startedScheduleId: String?
        var endedSessionId: String?
        var createdCompanion: Companion?
        var startedScheduleCompanion: Companion?
        let timeline: Timeline?
        init(statuses: [String], timeline: Timeline? = nil) {
            self.statuses = statuses
            self.timeline = timeline
        }
        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func createResume(rawText: String) async throws -> ResumeRead {
            ResumeRead(id: "r-1", version: 1, is_current: true)
        }
        func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead {
            createdCompanion = companion
            return SessionRead(id: "s-1", status: "created", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func getSession(id: String) async throws -> SessionRead {
            let s = statuses.isEmpty ? "ready" : statuses.removeFirst()
            return SessionRead(id: "s-1", status: s, livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func join(sessionId: String) async throws -> JoinResponse {
            joined = true
            return JoinResponse(livekit_room: "r", livekit_token: "tok")
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
            startedScheduleId = id
            startedScheduleCompanion = companion
            return ScheduleStartRead(
                schedule: InterviewScheduleRead(
                    id: id,
                    position_round_id: "pr-1",
                    scheduled_at: "2026-06-03T15:00:00+08:00",
                    timezone: "Asia/Shanghai",
                    duration_minutes: 30,
                    status: "preparing",
                    session_id: "s-1",
                    raw_command: "明天下午三点产品二面",
                    created_at: "2026-06-02T18:00:00Z"
                ),
                session: SessionRead(
                    id: "s-1",
                    status: "questions_generating",
                    livekit_room: nil,
                    failure_reason: nil,
                    total_cost_usd: nil
                )
            )
        }
        func agentHome() async throws -> AgentHomeRead {
            throw TransportError(message: "not used")
        }
        func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead {
            PositionRead(id: positionId, title: "产品经理", company: "字节")
        }
        func endSession(id: String) async throws -> SessionRead {
            timeline?.events.append("backend-ended")
            endedSessionId = id
            return SessionRead(id: id, status: "ended", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func sessionResults(id: String) async throws -> SessionResultRead {
            SessionResultRead(
                session_id: id,
                overall_score: 82,
                dimension_scores: ["product_sense": .int(82)],
                per_question_review: [],
                coaching_plan: [
                    "immediate_focus": .string("补充结构化表达"),
                    "next_session_suggestion": .string("继续练一轮")
                ],
                is_partial: false
            )
        }
    }
    final class FakeLK: LiveKitControlling {
        var connected = false
        var microphoneEnabled = false
        var localIdentity = "cand-1"
        let timeline: Timeline?
        private var onSegment: ((String, String, String, Bool) -> Void)?
        private var onParticipantAttributes: ((String, [String: String]) -> Void)?
        private var onCaptionChunk: ((String, String, String) -> Void)?
        private var onAudioRecoveryFailed: ((String) -> Void)?

        init(timeline: Timeline? = nil) {
            self.timeline = timeline
        }

        func connect(url: String, token: String,
                     onSegment: @escaping (String, String, String, Bool) -> Void,
                     onParticipantAttributes: @escaping (String, [String: String]) -> Void,
                     onCaptionChunk: @escaping (String, String, String) -> Void,
                     onState: @escaping (Bool) -> Void,
                     onAudioRecoveryFailed: @escaping (String) -> Void) async throws {
            connected = true
            microphoneEnabled = true
            self.onSegment = onSegment
            self.onParticipantAttributes = onParticipantAttributes
            self.onCaptionChunk = onCaptionChunk
            self.onAudioRecoveryFailed = onAudioRecoveryFailed
            onState(true)
        }
        func connectHomeVoice(url: String, token: String,
                              onSessionEvent: @escaping (HomeVoiceSessionEvent) -> Void,
                              onNavigateInterview: @escaping (Data) -> Void,
                              onNavigateHomeAction: @escaping (Data) -> Void,
                              onState: @escaping (Bool) -> Void,
                              onAudioRecoveryFailed: @escaping (String) -> Void) async throws {
            _ = onSessionEvent
            _ = onNavigateInterview
            _ = onNavigateHomeAction
            try await connect(
                url: url,
                token: token,
                onSegment: { _, _, _, _ in },
                onParticipantAttributes: { _, _ in },
                onCaptionChunk: { _, _, _ in },
                onState: onState,
                onAudioRecoveryFailed: onAudioRecoveryFailed
            )
        }
        func disconnect() async {
            timeline?.events.append("room-disconnected")
            connected = false
        }
        func setMicrophone(enabled: Bool) async throws { microphoneEnabled = enabled }

        func emitCandidateFinal(_ text: String) {
            onSegment?(UUID().uuidString, localIdentity, text, true)
        }

        func emitAttributes(identity: String = "agent-lead", _ attributes: [String: String]) {
            onParticipantAttributes?(identity, attributes)
        }

        func emitCaptionChunk(streamId: String = "caption-1", speaker: String, text: String) {
            onCaptionChunk?(streamId, speaker, text)
        }

        func emitAudioRecoveryFailure(_ message: String) {
            onAudioRecoveryFailed?(message)
        }
    }

    final class FakeMicrophonePermission: MicrophonePermissionProviding {
        var status: MicrophonePermissionStatus
        private(set) var openSettingsCount = 0

        init(status: MicrophonePermissionStatus) {
            self.status = status
        }

        func openSettings() {
            openSettingsCount += 1
        }
    }

    func test_start_reachesLiveAfterReady() async throws {
        let api = FakeAPI(statuses: ["created", "ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)
        await session.start(positionRoundId: "pr-1")
        XCTAssertTrue(api.joined)
        XCTAssertEqual(api.createdCompanion, .qinglan)
        XCTAssertTrue(lk.connected)
        XCTAssertEqual(session.phase, .live)
    }

    func test_startReflectsRealMicrophonePermissionState() async throws {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let permission = FakeMicrophonePermission(status: .denied)
        let session = InterviewSession(
            config: .default,
            api: api,
            liveKit: lk,
            microphonePermission: permission,
            pollInterval: 0
        )

        await session.start(positionRoundId: "pr-1")

        XCTAssertEqual(session.phase, .live)
        XCTAssertTrue(lk.connected)
        XCTAssertFalse(session.microphonePermissionGranted)
        XCTAssertFalse(session.canEnterRoom)

        permission.status = .allowed
        session.refreshMicrophonePermission()

        XCTAssertTrue(session.microphonePermissionGranted)
    }

    func test_startSchedule_reusesScheduleSessionAndReachesLive() async throws {
        let api = FakeAPI(statuses: ["questions_generating", "ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)

        await session.start(scheduleId: "sch-1")

        XCTAssertEqual(api.startedScheduleId, "sch-1")
        XCTAssertEqual(api.startedScheduleCompanion, .qinglan)
        XCTAssertEqual(session.sessionId, "s-1")
        XCTAssertTrue(api.joined)
        XCTAssertTrue(lk.connected)
        XCTAssertEqual(session.phase, .live)
    }

    func test_candidatePauseAndResumeVoiceCommandsToggleMicrophone() async throws {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)

        await session.start(positionRoundId: "pr-1")
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(lk.microphoneEnabled)

        lk.emitCandidateFinal("青岚，先暂停一下")
        await waitUntil { session.isPaused }

        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(lk.microphoneEnabled)

        lk.emitCandidateFinal("继续面试")
        await waitUntil { !session.isPaused }

        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(lk.microphoneEnabled)
    }

    func test_liveKitAudioRecoveryFailureFailsCleanly() async throws {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)
        await session.start(positionRoundId: "pr-1")

        lk.emitAudioRecoveryFailure("面试音频恢复失败，请重新进入房间。")
        await waitUntil {
            if case .failed = session.phase { return true }
            return false
        }

        XCTAssertEqual(session.phase, .failed("面试音频恢复失败，请重新进入房间。"))
        XCTAssertFalse(session.connected)
        XCTAssertEqual(session.connectionStatus, .disconnected)
    }

    func test_endDisconnectsRoomAndEndsBackendSession() async throws {
        let timeline = Timeline()
        let api = FakeAPI(statuses: ["ready"], timeline: timeline)
        let lk = FakeLK(timeline: timeline)
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)

        await session.start(positionRoundId: "pr-1")
        await session.end()

        XCTAssertEqual(api.endedSessionId, "s-1")
        XCTAssertFalse(lk.connected)
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(timeline.events, ["backend-ended", "room-disconnected"])
    }

    func test_leaveIfActiveDisconnectsOnceAndIsNoOpAfterEnd() async throws {
        let timeline = Timeline()
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"], timeline: timeline),
            liveKit: FakeLK(timeline: timeline),
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        await session.leaveIfActive()
        await session.leaveIfActive()

        XCTAssertEqual(timeline.events, ["room-disconnected"])
        XCTAssertFalse(session.connected)
        XCTAssertFalse(session.microphonePermissionGranted)
        XCTAssertEqual(session.connectionStatus, .disconnected)

        let endedTimeline = Timeline()
        let endedSession = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"], timeline: endedTimeline),
            liveKit: FakeLK(timeline: endedTimeline),
            pollInterval: 0
        )
        await endedSession.start(positionRoundId: "pr-1")
        await endedSession.end()
        await endedSession.leaveIfActive()

        XCTAssertEqual(endedTimeline.events, ["backend-ended", "room-disconnected"])
        XCTAssertEqual(endedSession.phase, .done)
    }

    func test_cancelRoomEntryThenDisappearDoesNotDoubleDisconnect() async throws {
        let timeline = Timeline()
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"], timeline: timeline),
            liveKit: FakeLK(timeline: timeline),
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        await session.cancelRoomEntry()
        await session.leaveIfActive()

        XCTAssertEqual(timeline.events, ["room-disconnected"])
        XCTAssertFalse(session.connected)
        XCTAssertEqual(session.phase, .idle)
    }

    func test_showResultUsesExistingSessionIdWithoutJoiningRoom() async throws {
        let api = FakeAPI(statuses: [])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)

        session.showResult(sessionId: "s-scored")
        let result = try await session.fetchResult()

        XCTAssertEqual(session.sessionId, "s-scored")
        XCTAssertEqual(session.phase, .done)
        XCTAssertFalse(lk.connected)
        XCTAssertEqual(result.session_id, "s-scored")
    }

    func test_roomEntryWaitsForBackendInRoomPhase() async {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: api,
            liveKit: lk,
            microphonePermission: FakeMicrophonePermission(status: .allowed),
            pollInterval: 0
        )

        XCTAssertEqual(session.roomPhase, .connecting)
        XCTAssertFalse(session.canEnterRoom)

        await session.start(positionRoundId: "pr-1")

        XCTAssertTrue(session.canEnterRoom)
        XCTAssertEqual(session.roomPhase, .connecting)

        lk.emitAttributes([
            "role": "lead",
            "status": "asking",
            "question_index": "0",
            "question_total": "6",
            "phase": "in_room",
        ])
        await waitUntil { session.roomPhase == .inRoom }

        XCTAssertEqual(session.roomPhase, .inRoom)
        XCTAssertEqual(session.roomSpeaker, .interviewer)
    }

    func test_connectingRoomPhaseProjectsInlinePanelStateBeforeBackendInRoom() async {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: api,
            liveKit: lk,
            microphonePermission: FakeMicrophonePermission(status: .denied),
            pollInterval: 0
        )

        await session.start(positionRoundId: "pr-1")

        XCTAssertEqual(session.roomPhase, .connecting)
        XCTAssertFalse(session.canEnterRoom)

        let presentation = InterviewPanelPresentation(session: session)

        XCTAssertEqual(presentation.headerStatus, .connected)
        XCTAssertEqual(presentation.leadTile.statusStyle.label, "连接中")
        XCTAssertEqual(presentation.leadTile.statusStyle.dotColor, DeepSpaceTheme.auroraCyan)
        XCTAssertEqual(presentation.panelistTile.statusStyle.label, "待加入")
        XCTAssertEqual(presentation.panelistTile.statusStyle.dotColor, Fig.amber)
        XCTAssertEqual(presentation.candidate.statusText, "待开麦 · 开启麦克风")
        XCTAssertEqual(presentation.caption.text, "正在接入面试官，正在同步本场题单…")
        XCTAssertFalse(presentation.answerControlEnabled)
    }

    func test_failedRoomPhaseProjectsFriendlyInlineRetryCopy() async {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: api,
            liveKit: lk,
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        lk.emitAudioRecoveryFailure("low-level audio graph failed")
        await waitUntil {
            if case .failed = session.phase { return true }
            return false
        }

        let presentation = InterviewPanelPresentation(session: session)

        XCTAssertEqual(presentation.caption.speakerLabel, "主面试官 · 连接中")
        XCTAssertEqual(presentation.caption.dotColor, Fig.amber)
        XCTAssertEqual(presentation.caption.text, "连接异常，正在重试…")
        XCTAssertFalse(presentation.answerControlEnabled)
    }

    func test_backendParticipantAttributesDriveRoomStateAndQuestionProgress() async {
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"]),
            liveKit: lk,
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        lk.emitAttributes(identity: "agent-jury", [
            "role": "jury",
            "status": "observing",
            "question_index": "1",
            "question_total": "6",
            "phase": "in_room",
        ])
        lk.emitAttributes([
            "role": "lead",
            "status": "listening",
            "question_index": "1",
            "question_total": "6",
            "phase": "in_room",
        ])
        await waitUntil { session.roomSpeaker == .candidate }

        XCTAssertEqual(session.roomPhase, .inRoom)
        XCTAssertEqual(session.roomSpeaker, .candidate)
        XCTAssertEqual(session.panelParticipants.map(\.status), [.listening, .observing, .answering])
        XCTAssertEqual(session.currentQuestionIndex, 2)
        XCTAssertEqual(session.totalQuestions, 6)

        lk.emitAttributes([
            "role": "lead",
            "status": "asking",
            "question_index": "2",
            "question_total": "6",
            "phase": "in_room",
        ])
        await waitUntil { session.roomSpeaker == .interviewer && session.currentQuestionIndex == 3 }

        XCTAssertEqual(session.panelParticipants.map(\.status), [.asking, .observing, .listening])

        lk.emitAttributes([
            "role": "lead",
            "status": "asking",
            "question_index": "2",
            "question_total": "6",
            "phase": "ending",
        ])
        await waitUntil { session.roomPhase == .leaving }

        XCTAssertEqual(session.roomPhase, .leaving)
    }

    func test_leadStateDoesNotCreateVirtualPanelist() async {
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"]),
            liveKit: lk,
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        lk.emitAttributes([
            "role": "lead",
            "status": "asking",
            "question_index": "0",
            "question_total": "6",
            "phase": "in_room",
        ])
        await waitUntil { session.panelParticipants[0].status == .asking }

        XCTAssertEqual(session.panelParticipants.map(\.role), [.lead, .candidate])
        XCTAssertEqual(session.panelParticipants.map(\.status), [.asking, .listening])
    }

    func test_initialRoomStateDoesNotSynthesizeQuestionProgressOrJury() {
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: []),
            liveKit: FakeLK(),
            pollInterval: 0
        )

        XCTAssertEqual(session.currentQuestionIndex, 0)
        XCTAssertEqual(session.totalQuestions, 0)
        XCTAssertEqual(session.panelParticipants.map(\.role), [.lead, .candidate])
        XCTAssertFalse(session.interviewerReady)
        XCTAssertFalse(session.questionSetSynced)
    }

    func test_transcriptTextStreamChunksAppendToLiveCaption() async {
        let lk = FakeLK()
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"]),
            liveKit: lk,
            pollInterval: 0
        )
        await session.start(positionRoundId: "pr-1")

        XCTAssertEqual(session.liveCaptionText, "")

        lk.emitCaptionChunk(speaker: "lead", text: "先讲讲")
        lk.emitCaptionChunk(speaker: "lead", text: "你最近的项目。")
        await waitUntil { session.liveCaptionText == "先讲讲你最近的项目。" }

        XCTAssertEqual(session.liveCaptionText, "先讲讲你最近的项目。")

        lk.emitCaptionChunk(streamId: "caption-2", speaker: "candidate", text: "我最近负责的是增长项目。")
        await waitUntil { session.liveCaptionText == "我最近负责的是增长项目。" }

        XCTAssertEqual(session.liveCaptionText, "我最近负责的是增长项目。")
    }

    func test_leaveDecisionCanContinueOrFinishAndGenerateReview() async {
        let api = FakeAPI(statuses: ["ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)
        await session.start(positionRoundId: "pr-1")
        lk.emitAttributes([
            "role": "lead",
            "status": "asking",
            "question_index": "0",
            "question_total": "6",
            "phase": "in_room",
        ])
        await waitUntil { session.roomPhase == .inRoom }

        session.requestLeave()
        XCTAssertEqual(session.roomPhase, .leaving)

        session.continueInterview()
        XCTAssertEqual(session.roomPhase, .inRoom)

        session.requestLeave()
        await session.finishAndGenerateReview()

        XCTAssertEqual(api.endedSessionId, "s-1")
        XCTAssertEqual(session.phase, .done)
    }

    func test_resultPresentationMapsFixedPMDimensionsAndWeakPracticeTarget() {
        let result = SessionResultRead(
            session_id: "s-1",
            overall_score: 76,
            dimension_scores: [
                "metric": .int(58),
                "solution": .int(74),
                "user_insight": .int(82),
                "tradeoff": .int(70),
                "need_dig": .int(78),
            ],
            per_question_review: [],
            coaching_plan: [
                "immediate_focus": .string("补足衡量指标"),
                "position_round_id": .string("pr-1"),
            ],
            is_partial: false
        )

        let presentation = ResultPresentation(result: result)

        XCTAssertEqual(presentation.overallScore, 76)
        XCTAssertEqual(presentation.dimensions.map(\.label), ["用户洞察", "需求挖掘", "方案设计", "取舍判断", "衡量指标"])
        XCTAssertEqual(presentation.dimensions.map(\.score), [82, 78, 74, 70, 58])
        XCTAssertEqual(presentation.dimensions.filter(\.isWeak).map(\.key), ["metric"])
        XCTAssertEqual(presentation.practiceItem.actionType, "practice_weakness")
        XCTAssertEqual(
            presentation.practiceItem.target,
            ["position_round_id": "pr-1", "session_id": "s-1", "weak_dimension": "metric"]
        )
    }

    func test_resultPresentationPrefersTypedResultContract() throws {
        let data = """
        {
          "session_id": "s-typed",
          "overall_score": 81,
          "dimension_scores": {"metric": 99, "solution": 20},
          "dimensions": [
            {"key": "solution", "label": "方案设计", "score": 76, "is_weakest": false},
            {"key": "metric", "label": "衡量指标", "score": 42, "is_weakest": true}
          ],
          "weakest_dimension": "metric",
          "practice_round_id": "pr-typed",
          "tip": "先把指标口径说清楚。",
          "per_question_review": [],
          "coaching_plan": {"immediate_focus": ["legacy value"]},
          "is_partial": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SessionResultRead.self, from: data)
        let presentation = ResultPresentation(result: result)

        XCTAssertEqual(presentation.dimensions.map(\.score), [76, 42])
        XCTAssertEqual(presentation.dimensions.filter(\.isWeak).map(\.key), ["metric"])
        XCTAssertEqual(presentation.tip, "先把指标口径说清楚。")
        XCTAssertEqual(presentation.practiceItem.target["position_round_id"], "pr-typed")
    }

    func test_resultPresentationDoesNotSynthesizeReviewCopyWhenServerOmitsIt() {
        let result = SessionResultRead(
            session_id: "s-no-copy",
            overall_score: 80,
            dimension_scores: ["metric": .int(80)],
            per_question_review: [],
            coaching_plan: [:],
            is_partial: false
        )

        let presentation = ResultPresentation(result: result)

        XCTAssertEqual(presentation.tip, "")
        XCTAssertEqual(presentation.practiceItem.reason, "")
    }

    func test_questionSummariesDoNotInventCompletedQuestionCopy() {
        let result = SessionResultRead(
            session_id: "s-no-review",
            overall_score: 80,
            dimension_scores: ["metric": .int(80)],
            per_question_review: [
                [:],
                ["weaknesses": .array([])],
            ],
            coaching_plan: [:],
            is_partial: false
        )

        XCTAssertEqual(result.questionSummaries, [])
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
