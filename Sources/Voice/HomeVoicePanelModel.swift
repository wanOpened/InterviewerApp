import Foundation
import Observation

enum HomeVoicePanelState: String, Equatable {
    case idle
    case connecting
    case speaking
    case listening
    case thinking
}

enum HomeVoiceTranscriptSpeaker: Equatable {
    case user
    case agent
}

enum HomeVoiceSessionEvent: Equatable {
    case connected
    case disconnected
    case agentSpeakingChanged(Bool)
    case localSpeakingChanged(Bool)
    case toolActivityChanged(Bool)
    case transcript(text: String, isFinal: Bool, speaker: HomeVoiceTranscriptSpeaker)
}

struct HomeVoiceNavigateInterviewPayload: Decodable, Equatable {
    let sessionId: String

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }

    static func decode(_ data: Data) throws -> HomeVoiceNavigateInterviewPayload {
        try JSONDecoder().decode(HomeVoiceNavigateInterviewPayload.self, from: data)
    }
}

struct HomeVoiceNavigateHomeActionPayload: Decodable, Equatable {
    struct Target: Decodable, Equatable {
        let scheduleId: String?
        let positionId: String?

        private enum CodingKeys: String, CodingKey {
            case scheduleId = "schedule_id"
            case positionId = "position_id"
        }
    }

    let type: String
    let route: String
    let payload: Target

    static func decode(_ data: Data) throws -> HomeVoiceNavigateHomeActionPayload {
        try JSONDecoder().decode(HomeVoiceNavigateHomeActionPayload.self, from: data)
    }
}

enum HomeVoiceEditorRoute: Equatable {
    case resume(scheduleId: String?, positionId: String?)
    case jd(scheduleId: String?, positionId: String?)
}

enum HomeCompanionMood: CaseIterable, Equatable {
    case idle
    case attention
    case success
    case error

    var qinglanState: QinglanState {
        switch self {
        case .idle:
            return .idle
        case .attention:
            return .attention
        case .success:
            return .success
        case .error:
            return .error
        }
    }
}

@MainActor
@Observable
final class HomeVoicePanelModel {
    private static let connectionErrorMessage = "语音连接暂时不可用，请稍后再试。"

    private(set) var isInlineInteractionActive = false
    private(set) var state: HomeVoicePanelState = .idle
    private(set) var transcript = ""
    private(set) var assistantMessage = ""
    private(set) var errorMessage: String?
    private(set) var join: HomeVoiceJoinResponse?

    private let api: APIClienting
    private let liveKit: LiveKitControlling
    private let liveKitURL: String
    private var onNavigateInterview: (String) -> Void
    private var onOpenEditor: (HomeVoiceEditorRoute) -> Void
    private var lifecycleGeneration = 0
    private var agentSpeaking = false
    private var localSpeaking = false
    private var toolActive = false

    init(
        api: APIClienting,
        liveKit: LiveKitControlling,
        liveKitURL: String,
        onNavigateInterview: @escaping (String) -> Void = { _ in },
        onOpenEditor: @escaping (HomeVoiceEditorRoute) -> Void = { _ in }
    ) {
        self.api = api
        self.liveKit = liveKit
        self.liveKitURL = liveKitURL
        self.onNavigateInterview = onNavigateInterview
        self.onOpenEditor = onOpenEditor
    }

    var currentContext: AgentHomeRead? {
        join?.current_context
    }

    var qinglanState: QinglanState {
        switch state {
        case .idle:
            return .idle
        case .connecting:
            return .connecting
        case .speaking:
            return .speaking
        case .listening:
            return .listening
        case .thinking:
            return .thinking
        }
    }

    var companionMood: HomeCompanionMood {
        switch state {
        case .idle:
            return .idle
        case .connecting, .listening, .thinking, .speaking:
            return .attention
        }
    }

    func openInlineInteraction() {
        isInlineInteractionActive = true
        errorMessage = nil
    }

    func setNavigateInterviewHandler(_ handler: @escaping (String) -> Void) {
        onNavigateInterview = handler
    }

    func setOpenEditorHandler(_ handler: @escaping (HomeVoiceEditorRoute) -> Void) {
        onOpenEditor = handler
    }

    func startInlineAgent() async {
        await start()
    }

    func closeInlineInteraction() async {
        await stop()
    }

    func openPanel() {
        openInlineInteraction()
    }

    func dismissPanel() async {
        await closeInlineInteraction()
    }

    func start() async {
        guard state == .idle else { return }
        let generation = nextLifecycleGeneration()
        isInlineInteractionActive = true
        state = .connecting
        errorMessage = nil
        transcript = ""
        assistantMessage = ""
        agentSpeaking = false
        localSpeaking = false
        toolActive = false

        do {
            try await api.ensureUser()
            guard isCurrentStart(generation) else { return }
            let joined = try await api.joinHomeVoice()
            guard isCurrentStart(generation) else { return }
            join = joined
            try await liveKit.connectHomeVoice(
                url: liveKitURL,
                token: joined.livekit_token,
                onSessionEvent: { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.isCurrentStart(generation) else { return }
                        self.apply(event)
                    }
                },
                onNavigateInterview: { [weak self] payload in
                    Task { @MainActor in
                        guard let self, self.isCurrentStart(generation) else { return }
                        await self.handleNavigateInterview(payload)
                    }
                },
                onNavigateHomeAction: { [weak self] payload in
                    Task { @MainActor in
                        guard let self, self.isCurrentStart(generation) else { return }
                        await self.handleNavigateHomeAction(payload)
                    }
                },
                onState: { [weak self] connected in
                    Task { @MainActor in
                        guard let self, self.isCurrentStart(generation) else { return }
                        self.apply(connected ? .connected : .disconnected)
                    }
                },
                onAudioRecoveryFailed: { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.isCurrentStart(generation) else { return }
                        await self.failAndReset()
                    }
                }
            )
            guard isCurrentStart(generation) else {
                await cleanupStaleConnection()
                return
            }
            if state == .connecting {
                apply(.connected)
            }
        } catch {
            guard isCurrentStart(generation) else { return }
            await failAndReset()
        }
    }

    func stop() async {
        lifecycleGeneration += 1
        await teardownSession()
    }

    func apply(_ event: HomeVoiceSessionEvent) {
        errorMessage = nil
        switch event {
        case .connected:
            agentSpeaking = true
            localSpeaking = false
            toolActive = false
            state = .speaking
        case .disconnected:
            resetToIdle(clearJoin: true)
        case .agentSpeakingChanged(let isSpeaking):
            agentSpeaking = isSpeaking
            recomputeStateAfterActivityChange(defaultWhenQuiet: .listening)
        case .localSpeakingChanged(let isSpeaking):
            localSpeaking = isSpeaking
            recomputeStateAfterActivityChange(defaultWhenQuiet: agentSpeaking ? .speaking : .listening)
        case .toolActivityChanged(let isActive):
            toolActive = isActive
            if isActive {
                localSpeaking = false
            }
            recomputeStateAfterActivityChange(defaultWhenQuiet: .speaking)
        case .transcript(let text, _, let speaker):
            switch speaker {
            case .user:
                transcript = text
                localSpeaking = true
                if !toolActive {
                    state = .listening
                }
            case .agent:
                assistantMessage = text
                agentSpeaking = true
                localSpeaking = false
                if !localSpeaking, !toolActive {
                    state = .speaking
                }
            }
        }
    }

    private func recomputeStateAfterActivityChange(defaultWhenQuiet: HomeVoicePanelState) {
        if toolActive {
            state = .thinking
        } else if localSpeaking {
            state = .listening
        } else if agentSpeaking {
            state = .speaking
        } else {
            state = defaultWhenQuiet
        }
    }

    private func handleNavigateInterview(_ payload: Data) async {
        do {
            let decoded = try HomeVoiceNavigateInterviewPayload.decode(payload)
            onNavigateInterview(decoded.sessionId)
            lifecycleGeneration += 1
            await teardownSession()
        } catch {
            errorMessage = Self.connectionErrorMessage
        }
    }

    private func handleNavigateHomeAction(_ payload: Data) async {
        do {
            let decoded = try HomeVoiceNavigateHomeActionPayload.decode(payload)
            switch decoded.type {
            case "open_resume_editor":
                onOpenEditor(
                    .resume(
                        scheduleId: decoded.payload.scheduleId,
                        positionId: decoded.payload.positionId
                    )
                )
            case "open_jd_editor":
                onOpenEditor(
                    .jd(
                        scheduleId: decoded.payload.scheduleId,
                        positionId: decoded.payload.positionId
                    )
                )
            default:
                throw TransportError(message: "unsupported home voice action")
            }
            lifecycleGeneration += 1
            await teardownSession()
        } catch {
            errorMessage = Self.connectionErrorMessage
        }
    }

    private func failAndReset() async {
        errorMessage = Self.connectionErrorMessage
        assistantMessage = Self.connectionErrorMessage
        lifecycleGeneration += 1
        await teardownSession()
    }

    private func teardownSession() async {
        try? await liveKit.setMicrophone(enabled: false)
        await liveKit.disconnect()
        resetToIdle(clearJoin: true)
        isInlineInteractionActive = false
    }

    private func resetToIdle(clearJoin: Bool) {
        state = .idle
        agentSpeaking = false
        localSpeaking = false
        toolActive = false
        if clearJoin {
            join = nil
        }
    }

    private func nextLifecycleGeneration() -> Int {
        lifecycleGeneration += 1
        return lifecycleGeneration
    }

    private func isCurrentStart(_ generation: Int) -> Bool {
        lifecycleGeneration == generation && isInlineInteractionActive
    }

    private func cleanupStaleConnection() async {
        try? await liveKit.setMicrophone(enabled: false)
        await liveKit.disconnect()
    }
}
