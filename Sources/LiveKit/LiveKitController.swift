import AVFoundation
import Foundation
import LiveKit

protocol LiveKitControlling: AnyObject {
    /// Connect, publish mic (MICROPHONE source), and start receiving room state and captions.
    func connect(url: String, token: String,
                 onSegment: @escaping (_ segmentId: String, _ sender: String,
                                       _ text: String, _ isFinal: Bool) -> Void,
                 onParticipantAttributes: @escaping (_ identity: String,
                                                      _ attributes: [String: String]) -> Void,
                 onCaptionChunk: @escaping (_ streamId: String, _ speaker: String, _ text: String) -> Void,
                 onState: @escaping (_ connected: Bool) -> Void,
                 onAudioRecoveryFailed: @escaping (_ message: String) -> Void) async throws
    func connectHomeVoice(url: String, token: String,
                          onSessionEvent: @escaping (HomeVoiceSessionEvent) -> Void,
                          onNavigateInterview: @escaping (Data) -> Void,
                          onNavigateHomeAction: @escaping (Data) -> Void,
                          onState: @escaping (_ connected: Bool) -> Void,
                          onAudioRecoveryFailed: @escaping (_ message: String) -> Void) async throws
    func activateHomeVoice() async throws
    func setMicrophone(enabled: Bool) async throws
    func disconnect() async
    var localIdentity: String { get }
}

final class LiveKitController: NSObject, LiveKitControlling, RoomDelegate, @unchecked Sendable {
    private let room = Room()
    private(set) var localIdentity: String = ""
    private var onParticipantAttributes: ((String, [String: String]) -> Void)?
    private var onAudioRecoveryFailed: ((String) -> Void)?
    private var onHomeVoiceSessionEvent: ((HomeVoiceSessionEvent) -> Void)?
    private var onHomeVoiceNavigateInterview: ((Data) -> Void)?
    private var onHomeVoiceNavigateHomeAction: ((Data) -> Void)?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var connected = false
    private var microphoneDesired = false

    override init() {
        super.init()
        // https://docs.livekit.io/home/client/state/participant-attributes
        // RoomDelegate receives participant attribute changes.
        room.add(delegate: self)
        installAudioSessionObservers()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    func connect(url: String, token: String,
                 onSegment: @escaping (String, String, String, Bool) -> Void,
                 onParticipantAttributes: @escaping (String, [String: String]) -> Void,
                 onCaptionChunk: @escaping (String, String, String) -> Void,
                 onState: @escaping (Bool) -> Void,
                 onAudioRecoveryFailed: @escaping (String) -> Void) async throws {
        self.onParticipantAttributes = onParticipantAttributes
        self.onAudioRecoveryFailed = onAudioRecoveryFailed
        #if targetEnvironment(simulator)
        // The iOS Simulator's voice-processing (AEC) audio unit faults
        // (downlink DSP / 0-channel converter errors), breaking mic capture and
        // playback. Disable voice processing so the simulator uses a plain
        // audio unit — enough to exercise the conversation flow. Real devices
        // keep VP (echo cancellation) enabled.
        do {
            try AudioManager.shared.setVoiceProcessingEnabled(false)
        } catch {
        }
        #endif
        // https://docs.livekit.io/intro/basics/connect.md
        let tokenPolicy = LiveKitJoinTokenPolicy(token: token)
        try await room.connect(url: url, token: token)
        connected = true
        localIdentity = room.localParticipant.identity?.stringValue ?? ""
        onState(true)

        // https://docs.livekit.io/transport/data/text-streams
        try await room.registerTextStreamHandler(for: "transcript") { [weak self] reader, participantIdentity in
            let speaker = reader.info.attributes["speaker"] ?? "lead"
            let isFinal = reader.info.attributes["final"] == "true"
            var text = ""
            for try await chunk in reader {
                text += chunk
                onCaptionChunk(reader.info.id, speaker, chunk)
            }
            let sender = speaker == "candidate"
                ? self?.localIdentity ?? participantIdentity.stringValue
                : participantIdentity.stringValue
            onSegment(reader.info.id, sender, text, isFinal)
        }

        // Interview tokens publish the microphone with .microphone source,
        // which the agent's RoomIO requires. Observe tokens are receive-only.
        if tokenPolicy.canPublish {
            try await room.localParticipant.setMicrophone(enabled: true)
            microphoneDesired = true
        } else {
            microphoneDesired = false
        }
        // Remote (agent) audio plays automatically via LiveKit's AudioManager.
    }

    func connectHomeVoice(url: String, token: String,
                          onSessionEvent: @escaping (HomeVoiceSessionEvent) -> Void,
                          onNavigateInterview: @escaping (Data) -> Void,
                          onNavigateHomeAction: @escaping (Data) -> Void,
                          onState: @escaping (Bool) -> Void,
                          onAudioRecoveryFailed: @escaping (String) -> Void) async throws {
        onHomeVoiceSessionEvent = onSessionEvent
        onHomeVoiceNavigateInterview = onNavigateInterview
        onHomeVoiceNavigateHomeAction = onNavigateHomeAction
        self.onAudioRecoveryFailed = onAudioRecoveryFailed
        #if targetEnvironment(simulator)
        do {
            try AudioManager.shared.setVoiceProcessingEnabled(false)
        } catch {
        }
        #endif
        // https://docs.livekit.io/intro/basics/connect.md
        try await room.connect(url: url, token: token)
        connected = true
        localIdentity = room.localParticipant.identity?.stringValue ?? ""
        onState(true)

        // Home Voice prejoins silently. The mic is enabled only after the user
        // taps Qinglan and `activateHomeVoice()` notifies the agent.
        // https://docs.livekit.io/transport/media/publish.md
        try await room.registerTextStreamHandler(for: "transcript") { [weak self] reader, participantIdentity in
            let speaker = reader.info.attributes["speaker"] ?? "lead"
            let isFinal = reader.info.attributes["final"] == "true"
            var text = ""
            for try await chunk in reader {
                text += chunk
            }
            let sender = speaker == "candidate"
                ? self?.localIdentity ?? participantIdentity.stringValue
                : participantIdentity.stringValue
            let transcriptSpeaker: HomeVoiceTranscriptSpeaker = sender == self?.localIdentity ? .user : .agent
            onSessionEvent(.transcript(text: text, isFinal: isFinal, speaker: transcriptSpeaker))
        }
    }

    func activateHomeVoice() async throws {
        // https://docs.livekit.io/transport/data/packets/
        try await room.localParticipant.publish(
            data: Data("{}".utf8),
            options: DataPublishOptions(topic: "home_voice.activate", reliable: true)
        )
    }

    func setMicrophone(enabled: Bool) async throws {
        // https://docs.livekit.io/transport/media/publish.md
        try await room.localParticipant.setMicrophone(enabled: enabled)
        microphoneDesired = enabled
    }

    func disconnect() async {
        // https://docs.livekit.io/intro/basics/connect.md#disconnect-from-a-room
        await room.disconnect()
        connected = false
        microphoneDesired = false
        onHomeVoiceSessionEvent = nil
        onHomeVoiceNavigateInterview = nil
        onHomeVoiceNavigateHomeAction = nil
    }

    // https://docs.livekit.io/home/client/state/participant-attributes
    func room(_ room: Room, participant: Participant, didUpdateAttributes attributes: [String: String]) {
        onParticipantAttributes?(participant.identity?.stringValue ?? "", participant.attributes)
    }

    // Verified against local LiveKit Swift SDK 2.x source on 2026-06-09:
    // RoomDelegate.room(_:didUpdateSpeakingParticipants:) surfaces VAD-active participants.
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        guard let onHomeVoiceSessionEvent else { return }
        let local = room.localParticipant.identity?.stringValue ?? localIdentity
        let localSpeaking = participants.contains { participant in
            participant.identity?.stringValue == local
        }
        let agentSpeaking = participants.contains { participant in
            participant.identity?.stringValue != local
        }
        onHomeVoiceSessionEvent(.localSpeakingChanged(localSpeaking))
        onHomeVoiceSessionEvent(.agentSpeakingChanged(agentSpeaking))
    }

    // Sources verified 2026-06-07:
    // - https://docs.livekit.io/transport/data/packets/
    // - livekit/client-sdk-swift RoomDelegate.room(_:participant:didReceiveData:forTopic:encryptionType:)
    func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType: EncryptionType
    ) {
        switch topic {
        case "navigate.interview":
            onHomeVoiceNavigateInterview?(data)
        case "navigate.home_action":
            onHomeVoiceNavigateHomeAction?(data)
        default:
            return
        }
    }

    private func installAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.recoverMicrophoneIfNeeded()
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType),
              type == .ended
        else { return }
        Task { [weak self] in
            await self?.recoverMicrophoneIfNeeded()
        }
    }

    private func recoverMicrophoneIfNeeded() async {
        guard connected, microphoneDesired else { return }
        do {
            // https://docs.livekit.io/transport/media/publish.md
            try await room.localParticipant.setMicrophone(enabled: true)
        } catch {
            connected = false
            microphoneDesired = false
            onAudioRecoveryFailed?("面试音频恢复失败，请重新进入房间。")
        }
    }
}
