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

private enum HomeVoiceLifecyclePhase {
    case idle
    case preparing
    case prepared
    case active
}

@MainActor
@Observable
final class HomeVoicePanelModel {
    private static let connectionErrorMessage = "语音连接暂时不可用，请稍后再试。"
    private static let activationRetryIntervalNanoseconds: UInt64 = 250_000_000
    private static let activationRetryAttempts = 32

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
    private var onOpenScheduleList: () -> Void
    private var lifecycleGeneration = 0
    private var lifecyclePhase: HomeVoiceLifecyclePhase = .idle
    private var agentSpeaking = false
    private var localSpeaking = false
    private var toolActive = false
    private var activationRetryTask: Task<Void, Never>?

    init(
        api: APIClienting,
        liveKit: LiveKitControlling,
        liveKitURL: String,
        onNavigateInterview: @escaping (String) -> Void = { _ in },
        onOpenEditor: @escaping (HomeVoiceEditorRoute) -> Void = { _ in },
        onOpenScheduleList: @escaping () -> Void = {}
    ) {
        self.api = api
        self.liveKit = liveKit
        self.liveKitURL = liveKitURL
        self.onNavigateInterview = onNavigateInterview
        self.onOpenEditor = onOpenEditor
        self.onOpenScheduleList = onOpenScheduleList
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

    func setOpenScheduleListHandler(_ handler: @escaping () -> Void) {
        onOpenScheduleList = handler
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

    @discardableResult
    func prepare() async -> Bool {
        switch lifecyclePhase {
        case .prepared, .active:
            return true
        case .preparing:
            while lifecyclePhase == .preparing {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return lifecyclePhase == .prepared || lifecyclePhase == .active
        case .idle:
            break
        }

        let generation = nextLifecycleGeneration()
        lifecyclePhase = .preparing
        errorMessage = nil

        do {
            try await api.ensureUser()
            guard isCurrentLifecycle(generation) else { return false }
            let joined = try await api.joinHomeVoice()
            guard isCurrentLifecycle(generation) else { return false }
            join = joined
            try await liveKit.connectHomeVoice(
                url: liveKitURL,
                token: joined.livekit_token,
                onSessionEvent: { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.isCurrentLifecycle(generation) else { return }
                        self.apply(event)
                    }
                },
                onNavigateInterview: { [weak self] payload in
                    Task { @MainActor in
                        guard let self, self.isCurrentLifecycle(generation) else { return }
                        await self.handleNavigateInterview(payload)
                    }
                },
                onNavigateHomeAction: { [weak self] payload in
                    Task { @MainActor in
                        guard let self, self.isCurrentLifecycle(generation) else { return }
                        await self.handleNavigateHomeAction(payload)
                    }
                },
                onState: { [weak self] connected in
                    Task { @MainActor in
                        guard let self, self.isCurrentLifecycle(generation) else { return }
                        self.apply(connected ? .connected : .disconnected)
                    }
                },
                onAudioRecoveryFailed: { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.isCurrentLifecycle(generation) else { return }
                        await self.failAndReset()
                    }
                }
            )
            guard isCurrentLifecycle(generation) else {
                await cleanupStaleConnection()
                return false
            }
            if lifecyclePhase == .preparing {
                lifecyclePhase = .prepared
            }
            return true
        } catch {
            guard isCurrentLifecycle(generation) else { return false }
            resetToIdle(clearJoin: true)
            isInlineInteractionActive = false
            return false
        }
    }

    func activate() async {
        if lifecyclePhase == .active {
            return
        }
        isInlineInteractionActive = true
        state = .connecting
        errorMessage = nil
        transcript = ""
        assistantMessage = ""
        agentSpeaking = false
        localSpeaking = false
        toolActive = false

        guard await prepare() else {
            await failAndReset()
            return
        }

        do {
            let activationGeneration = lifecycleGeneration
            try await liveKit.activateHomeVoice()
            try await liveKit.setMicrophone(enabled: true)
            lifecyclePhase = .active
            agentSpeaking = true
            localSpeaking = false
            toolActive = false
            state = .speaking
            startActivationRetryLoop(generation: activationGeneration)
        } catch {
            cancelActivationRetry()
            await failAndReset()
        }
    }

    func start() async {
        await activate()
    }

    func stop() async {
        lifecycleGeneration += 1
        await teardownSession()
    }

    func apply(_ event: HomeVoiceSessionEvent) {
        errorMessage = nil
        switch event {
        case .connected:
            if lifecyclePhase == .preparing || (lifecyclePhase == .prepared && !isInlineInteractionActive) {
                lifecyclePhase = .prepared
                if !isInlineInteractionActive {
                    state = .idle
                }
                return
            }
            lifecyclePhase = .active
            agentSpeaking = true
            localSpeaking = false
            toolActive = false
            state = .speaking
        case .disconnected:
            resetToIdle(clearJoin: true)
        case .agentSpeakingChanged(let isSpeaking):
            guard !shouldIgnorePassiveRoomEvent else { return }
            if isSpeaking {
                cancelActivationRetry()
            }
            agentSpeaking = isSpeaking
            recomputeStateAfterActivityChange(defaultWhenQuiet: .listening)
        case .localSpeakingChanged(let isSpeaking):
            guard !shouldIgnorePassiveRoomEvent else { return }
            localSpeaking = isSpeaking
            recomputeStateAfterActivityChange(defaultWhenQuiet: agentSpeaking ? .speaking : .listening)
        case .toolActivityChanged(let isActive):
            guard !shouldIgnorePassiveRoomEvent else { return }
            toolActive = isActive
            if isActive {
                localSpeaking = false
            }
            recomputeStateAfterActivityChange(defaultWhenQuiet: .speaking)
        case .transcript(let text, _, let speaker):
            guard !shouldIgnorePassiveRoomEvent else { return }
            switch speaker {
            case .user:
                transcript = text
                localSpeaking = true
                if !toolActive {
                    state = .listening
                }
            case .agent:
                cancelActivationRetry()
                assistantMessage = text
                agentSpeaking = true
                localSpeaking = false
                if !localSpeaking, !toolActive {
                    state = .speaking
                }
            }
        }
    }

    private var shouldIgnorePassiveRoomEvent: Bool {
        !isInlineInteractionActive && (lifecyclePhase == .preparing || lifecyclePhase == .prepared)
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
            case "create_schedule", "update_schedule", "cancel_schedule":
                onOpenScheduleList()
            default:
                return
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
        cancelActivationRetry()
        try? await liveKit.setMicrophone(enabled: false)
        await liveKit.disconnect()
        resetToIdle(clearJoin: true)
        isInlineInteractionActive = false
    }

    private func startActivationRetryLoop(generation: Int) {
        activationRetryTask?.cancel()
        activationRetryTask = Task { [weak self] in
            for _ in 0..<Self.activationRetryAttempts {
                try? await Task.sleep(nanoseconds: Self.activationRetryIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let shouldContinue = await self.retryActivationIfCurrent(generation)
                if !shouldContinue {
                    return
                }
            }
        }
    }

    private func retryActivationIfCurrent(_ generation: Int) async -> Bool {
        guard isCurrentLifecycle(generation),
              isInlineInteractionActive,
              lifecyclePhase == .active else {
            return false
        }
        try? await liveKit.activateHomeVoice()
        return true
    }

    private func cancelActivationRetry() {
        activationRetryTask?.cancel()
        activationRetryTask = nil
    }

    private func resetToIdle(clearJoin: Bool) {
        lifecyclePhase = .idle
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

    private func isCurrentLifecycle(_ generation: Int) -> Bool {
        lifecycleGeneration == generation
    }

    private func cleanupStaleConnection() async {
        try? await liveKit.setMicrophone(enabled: false)
        await liveKit.disconnect()
    }
}
