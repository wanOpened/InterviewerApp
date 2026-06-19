import Foundation
import Observation

struct InterviewRoomParticipant: Equatable {
    enum Role: Equatable, Hashable {
        case lead
        case panelist
        case candidate
    }

    let name: String
    let role: Role
    let status: RoomStatus
}

@MainActor
@Observable
final class InterviewSession {
    enum Phase: Equatable { case idle, preparing, live, finishing, done, failed(String) }
    enum ConnectionStatus: Equatable {
        case idle
        case preparingSession
        case requestingToken
        case joiningRoom
        case connected
        case leaving
        case disconnected
    }
    enum RoomMode: Equatable { case interview, observe }
    enum RoomPhase: Equatable { case connecting, inRoom, leaving }
    enum RoomSpeaker: Equatable { case interviewer, candidate }

    private(set) var phase: Phase = .idle
    private(set) var turns: [TranscriptTurn] = []
    private(set) var connected = false
    private(set) var isPaused = false
    private(set) var connectionStatus: ConnectionStatus = .idle
    private(set) var roomMode: RoomMode = .interview
    private(set) var roomPhase: RoomPhase = .connecting
    private(set) var roomSpeaker: RoomSpeaker = .interviewer
    private(set) var liveCaptionText = ""
    private(set) var microphonePermissionStatus: MicrophonePermissionStatus = .undetermined
    private(set) var microphonePermissionGranted = false
    private(set) var sessionId: String?
    private(set) var liveStartedAt: Date?   // set when the interview goes live; drives the elapsed timer
    var entryTitle = "青岚模拟面试"
    var entryMode = "完整模拟"
    private(set) var currentQuestionIndex = 0
    private(set) var totalQuestions = 0

    var canEnterRoom: Bool {
        phase == .live && connected && (roomMode == .observe || microphonePermissionGranted)
    }

    var interviewerReady: Bool {
        participantStatuses[.lead] != nil
    }

    var questionSetSynced: Bool {
        totalQuestions > 0
    }

    var panelParticipants: [InterviewRoomParticipant] {
        var participants = [
            InterviewRoomParticipant(
                name: "主面试官",
                role: .lead,
                status: participantStatuses[.lead] ?? .connecting
            ),
        ]
        if let panelistStatus = participantStatuses[.panelist] {
            participants.append(InterviewRoomParticipant(
                name: "评委",
                role: .panelist,
                status: panelistStatus
            ))
        }
        participants.append(
            InterviewRoomParticipant(
                name: "你 · 候选人",
                role: .candidate,
                status: participantStatuses[.candidate] ?? .connecting
            )
        )
        return participants
    }

    private let config: AppConfig
    private let api: APIClienting
    private let liveKit: LiveKitControlling
    private let microphonePermission: MicrophonePermissionProviding
    private let pollInterval: TimeInterval
    private var store: TranscriptStore?
    private var participantStatuses: [InterviewRoomParticipant.Role: RoomStatus] = [:]
    private var liveCaptionStreamId: String?

    var companion: Companion {
        config.selectedCompanion
    }

    init(config: AppConfig, api: APIClienting, liveKit: LiveKitControlling,
         microphonePermission: MicrophonePermissionProviding = SystemMicrophonePermissionProvider(),
         pollInterval: TimeInterval = 2.0) {
        self.config = config
        self.api = api
        self.liveKit = liveKit
        self.microphonePermission = microphonePermission
        self.pollInterval = pollInterval
    }

    func start(scheduleId: String) async {
        do {
            phase = .preparing
            prepareRoomState()
            connectionStatus = .preparingSession
            isPaused = false
            try await api.ensureUser()
            try await api.ensureResume()
            let started = try await api.startSchedule(
                id: scheduleId,
                companion: config.selectedCompanion
            )
            sessionId = started.session.id
            try await waitForReady(started.session.id)
            try await connectReadySession(started.session.id)
        } catch let e as APIError {
            connectionStatus = .disconnected
            phase = .failed(sessionStartFailureMessage(for: e))
        } catch {
            connectionStatus = .disconnected
            phase = .failed("\(error)")
        }
    }

    func start(positionRoundId: String) async {
        do {
            phase = .preparing
            prepareRoomState()
            connectionStatus = .preparingSession
            isPaused = false
            try await api.ensureUser()
            try await api.ensureResume()
            let created = try await api.createSession(
                positionRoundId: positionRoundId,
                companion: config.selectedCompanion
            )
            sessionId = created.id
            try await waitForReady(created.id)
            try await connectReadySession(created.id)
        } catch let e as APIError {
            connectionStatus = .disconnected
            phase = .failed(sessionStartFailureMessage(for: e))
        } catch {
            connectionStatus = .disconnected
            phase = .failed("\(error)")
        }
    }

    func resume(sessionId id: String) async {
        do {
            phase = .preparing
            prepareRoomState()
            connectionStatus = .preparingSession
            isPaused = false
            try await api.ensureUser()
            sessionId = id
            try await waitForReady(id)
            try await connectReadySession(id)
        } catch let e as APIError {
            connectionStatus = .disconnected
            phase = .failed("\(e.errorCode): \(e.userMessage)")
        } catch {
            connectionStatus = .disconnected
            phase = .failed("\(error)")
        }
    }

    private func waitForReady(_ id: String, maxAttempts: Int = 30) async throws {
        for _ in 0..<maxAttempts {
            let s = try await api.getSession(id: id)
            if s.status == "ready" || s.status == "in_progress" { return }
            if ["failed", "failed_partial", "expired", "cancelled"].contains(s.status) {
                throw TransportError(message: "session \(s.status): \(s.failure_reason ?? "")")
            }
            if pollInterval > 0 { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
        }
        throw TransportError(message: "session not ready in time")
    }

    private func connectReadySession(_ id: String) async throws {
        connectionStatus = .requestingToken
        let join = try await api.join(sessionId: id)
        let tokenPolicy = LiveKitJoinTokenPolicy(token: join.livekit_token)
        roomMode = tokenPolicy.isObserveInterview ? .observe : .interview
        connectionStatus = .joiningRoom

        store = nil
        try await liveKit.connect(
            url: config.livekitURL,
            token: join.livekit_token,
            onSegment: { [weak self] seg, sender, text, isFinal in
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if self.store == nil {
                        self.store = TranscriptStore(localIdentity: self.liveKit.localIdentity)
                    }
                    self.store?.ingest(segmentId: seg, senderIdentity: sender,
                                       text: text, isFinal: isFinal)
                    self.turns = self.store?.turns ?? []
                    if isFinal,
                       sender == self.liveKit.localIdentity,
                       let command = VoiceCommandInterpreter.interviewCommand(from: text) {
                        await self.apply(command)
                    }
                }
            },
            onParticipantAttributes: { [weak self] _, attributes in
                Task { @MainActor in
                    self?.applyParticipantAttributes(attributes)
                }
            },
            onCaptionChunk: { [weak self] streamId, _, text in
                Task { @MainActor in
                    self?.appendLiveCaptionChunk(streamId: streamId, text: text)
                }
            },
            onState: { [weak self] up in
                Task { @MainActor in
                    self?.connected = up
                    self?.connectionStatus = up ? .connected : .disconnected
                }
            },
            onAudioRecoveryFailed: { [weak self] message in
                Task { @MainActor in
                    self?.failAudioRecovery(message)
                }
            }
        )
        liveStartedAt = Date()
        connected = true
        if roomMode == .interview {
            refreshMicrophonePermission()
        } else {
            clearMicrophonePermissionState()
        }
        connectionStatus = .connected
        isPaused = false
        phase = .live
    }

    func refreshMicrophonePermission() {
        let status = microphonePermission.status
        microphonePermissionStatus = status
        microphonePermissionGranted = status.isAllowed
    }

    func openMicrophoneSettings() {
        microphonePermission.openSettings()
        refreshMicrophonePermission()
    }

    private func clearMicrophonePermissionState() {
        microphonePermissionStatus = .undetermined
        microphonePermissionGranted = false
    }

    func requestLeave() {
        guard roomPhase == .inRoom else { return }
        roomPhase = .leaving
    }

    func continueInterview() {
        guard roomPhase == .leaving, connected else { return }
        roomPhase = .inRoom
    }

    func finishAndGenerateReview() async {
        guard roomPhase == .leaving else { return }
        await end()
    }

    func cancelRoomEntry() async {
        guard roomPhase == .connecting else { return }
        await disconnectWithoutEnding()
    }

    func leaveIfActive() async {
        guard connected, phase != .done, phase != .finishing else { return }
        connectionStatus = .leaving
        await liveKit.disconnect()
        connected = false
        isPaused = false
        clearMicrophonePermissionState()
        connectionStatus = .disconnected
        roomPhase = .connecting
        roomSpeaker = .interviewer
        participantStatuses = [:]
        liveCaptionText = ""
        liveCaptionStreamId = nil
        liveStartedAt = nil
    }

    private func disconnectWithoutEnding() async {
        connectionStatus = .leaving
        await liveKit.disconnect()
        connected = false
        isPaused = false
        clearMicrophonePermissionState()
        connectionStatus = .disconnected
        roomPhase = .connecting
        roomSpeaker = .interviewer
        participantStatuses = [:]
        liveCaptionText = ""
        liveCaptionStreamId = nil
        liveStartedAt = nil
        phase = .idle
    }

    func pause() async {
        guard roomMode == .interview, phase == .live, connected, !isPaused else { return }
        do {
            try await liveKit.setMicrophone(enabled: false)
            isPaused = true
        } catch {
            phase = .failed("\(error)")
        }
    }

    func resume() async {
        guard roomMode == .interview, phase == .live, connected, isPaused else { return }
        do {
            try await liveKit.setMicrophone(enabled: true)
            isPaused = false
        } catch {
            phase = .failed("\(error)")
        }
    }

    func end() async {
        phase = .finishing
        roomPhase = .leaving
        connectionStatus = .leaving
        guard let sessionId else {
            phase = .failed("missing session id")
            return
        }
        do {
            _ = try await api.endSession(id: sessionId)
        } catch let e as APIError {
            phase = .failed("\(e.errorCode): \(e.userMessage)")
            return
        } catch {
            phase = .failed("\(error)")
            return
        }
        await liveKit.disconnect()
        connected = false
        isPaused = false
        clearMicrophonePermissionState()
        connectionStatus = .disconnected
        phase = .done
    }

    func fetchResult() async throws -> SessionResultRead {
        guard let sessionId else { throw TransportError(message: "missing session id") }
        return try await api.sessionResults(id: sessionId)
    }

    func showResult(sessionId id: String) {
        sessionId = id
        connected = false
        isPaused = false
        clearMicrophonePermissionState()
        connectionStatus = .disconnected
        roomPhase = .connecting
        phase = .done
    }

    private func apply(_ command: InterviewVoiceCommand) async {
        switch command {
        case .pause:
            await pause()
        case .resume:
            await resume()
        case .end:
            await end()
        }
    }

    private func failAudioRecovery(_ message: String) {
        connected = false
        isPaused = false
        clearMicrophonePermissionState()
        connectionStatus = .disconnected
        phase = .failed(message)
    }

    private func applyParticipantAttributes(_ attributes: [String: String]) {
        if let phase = attributes["phase"] {
            switch phase {
            case "connecting": roomPhase = .connecting
            case "in_room": roomPhase = .inRoom
            case "ending": roomPhase = .leaving
            default: break
            }
        }

        if let questionIndex = attributes["question_index"].flatMap(Int.init) {
            currentQuestionIndex = max(1, questionIndex + 1)
        }
        if let questionTotal = attributes["question_total"].flatMap(Int.init), questionTotal > 0 {
            totalQuestions = questionTotal
        }

        guard let role = participantRole(from: attributes["role"]),
              let status = roomStatus(from: attributes["status"])
        else { return }

        participantStatuses[role] = status
        switch (role, status) {
        case (.lead, .asking):
            roomSpeaker = .interviewer
            participantStatuses[.candidate] = .listening
        case (.lead, .listening):
            roomSpeaker = .candidate
            participantStatuses[.candidate] = .answering
        case (.candidate, .answering):
            roomSpeaker = .candidate
        case (.candidate, .listening):
            roomSpeaker = .interviewer
        default:
            break
        }
    }

    private func participantRole(from value: String?) -> InterviewRoomParticipant.Role? {
        switch value {
        case "lead": return .lead
        case "jury": return .panelist
        case "candidate": return .candidate
        default: return nil
        }
    }

    private func roomStatus(from value: String?) -> RoomStatus? {
        switch value {
        case "asking": return .asking
        case "listening": return .listening
        case "observing": return .observing
        case "answering": return .answering
        default: return nil
        }
    }

    private func appendLiveCaptionChunk(streamId: String, text: String) {
        if liveCaptionStreamId != streamId {
            liveCaptionStreamId = streamId
            liveCaptionText = ""
        }
        liveCaptionText += text
    }

    private func prepareRoomState() {
        connectionStatus = .idle
        roomMode = .interview
        roomPhase = .connecting
        roomSpeaker = .interviewer
        participantStatuses = [:]
        liveCaptionText = ""
        liveCaptionStreamId = nil
        currentQuestionIndex = 0
        totalQuestions = 0
        clearMicrophonePermissionState()
    }

    private func sessionStartFailureMessage(for error: APIError) -> String {
        if error.errorCode == "RESUME_REQUIRED" {
            return "先补充简历"
        }
        return "\(error.errorCode): \(error.userMessage)"
    }
}
