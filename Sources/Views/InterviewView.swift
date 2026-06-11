import SwiftUI

struct InterviewView: View {
    @Bindable var session: InterviewSession
    let practiceWeakness: (BriefingItem) -> Void
    let returnHome: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if session.phase == .done {
                VStack {
                    DoneView(
                        sessionId: session.sessionId,
                        companion: session.companion,
                        loadResult: { try await session.fetchResult() },
                        practiceWeakness: practiceWeakness,
                        returnHome: returnHome,
                        reportContext: ReportContext(company: session.entryTitle, round: nil, dateText: nil, durationText: nil)
                    )
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    RedesignInterviewRoomScreen(
                        session: session,
                        elapsed: elapsedText(now: timeline.date),
                        questionLabel: questionProgressLabel,
                        dismiss: dismiss
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            Task { await session.leaveIfActive() }
        }
    }

    private var questionProgressLabel: String {
        guard session.totalQuestions > 0, session.currentQuestionIndex > 0 else {
            return "题单同步中"
        }
        return "Q\(min(session.currentQuestionIndex, session.totalQuestions))/\(session.totalQuestions)"
    }

    private func elapsedText(now: Date) -> String {
        guard let started = session.liveStartedAt, session.phase == .live else { return "00:00" }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

}

struct InterviewPanelTilePresentation {
    let name: String
    let role: ParticipantTile.Role
    let state: ParticipantTile.State
    let subtitle: String?
    let statusStyle: StatusPillStyle

    var isActive: Bool {
        state == .active
    }
}

struct InterviewPanelCandidatePresentation {
    let statusText: String
    let statusColor: Color
    let isActive: Bool
    let canRequestMicrophone: Bool
}

struct InterviewPanelCaptionPresentation {
    let speakerLabel: String
    let dotColor: Color
    let textColor: Color
    let text: String
}

struct InterviewPanelPresentation {
    let headerStatus: RoomStatus
    let leadTile: InterviewPanelTilePresentation
    let panelistTile: InterviewPanelTilePresentation
    let candidate: InterviewPanelCandidatePresentation
    let caption: InterviewPanelCaptionPresentation
    let bottomHint: String
    let answerControlEnabled: Bool

    var participantTiles: [InterviewPanelTilePresentation] {
        [leadTile, panelistTile]
    }

    @MainActor
    init(session: InterviewSession) {
        let statuses = Dictionary(
            uniqueKeysWithValues: session.panelParticipants.map { ($0.role, $0.status) }
        )
        self.init(
            connected: session.connected,
            roomPhase: session.roomPhase,
            phase: session.phase,
            canEnterRoom: session.canEnterRoom,
            microphonePermissionGranted: session.microphonePermissionGranted,
            roomSpeaker: session.roomSpeaker,
            participantStatuses: statuses,
            liveCaptionText: session.liveCaptionText,
            questionSetSynced: session.questionSetSynced
        )
    }

    init(
        connected: Bool,
        roomPhase: InterviewSession.RoomPhase,
        phase: InterviewSession.Phase,
        canEnterRoom: Bool,
        microphonePermissionGranted: Bool,
        roomSpeaker: InterviewSession.RoomSpeaker,
        participantStatuses: [InterviewRoomParticipant.Role: RoomStatus],
        liveCaptionText: String,
        questionSetSynced: Bool
    ) {
        let leadStatus = participantStatuses[.lead]
        let panelistStatus = participantStatuses[.panelist]
        let candidateStatus = participantStatuses[.candidate] ?? .connecting
        let isConnectingPanel = roomPhase == .connecting || !questionSetSynced
        let isFailed: Bool
        if case .failed = phase {
            isFailed = true
        } else {
            isFailed = false
        }

        headerStatus = connected ? .connected : .connecting
        leadTile = InterviewPanelTilePresentation(
            name: "主面试官",
            role: .lead,
            state: leadStatus == .asking && !isConnectingPanel && !isFailed ? .active : .listening,
            subtitle: nil,
            statusStyle: isFailed
                ? .amber(label: "连接中")
                : isConnectingPanel
                    ? StatusPillStyle(for: .connecting)
                    : StatusPillStyle(for: leadStatus ?? .asking)
        )
        panelistTile = InterviewPanelTilePresentation(
            name: "评委",
            role: .panelist,
            state: panelistStatus == .asking && !isConnectingPanel && !isFailed ? .active : .listening,
            subtitle: "旁听",
            statusStyle: isConnectingPanel || isFailed || panelistStatus == nil
                ? .amber(label: "待加入")
                : StatusPillStyle(for: panelistStatus ?? .observing)
        )

        if microphonePermissionGranted {
            candidate = InterviewPanelCandidatePresentation(
                statusText: "聆听中 · 麦克风开",
                statusColor: candidateStatus == .answering ? DeepSpaceTheme.auroraCyan : Fig.onDarkMuted,
                isActive: candidateStatus == .answering && !isConnectingPanel && !isFailed,
                canRequestMicrophone: false
            )
        } else {
            candidate = InterviewPanelCandidatePresentation(
                statusText: "待开麦 · 开启麦克风",
                statusColor: Fig.amber,
                isActive: false,
                canRequestMicrophone: true
            )
        }

        if isFailed {
            caption = InterviewPanelCaptionPresentation(
                speakerLabel: "主面试官 · 连接中",
                dotColor: Fig.amber,
                textColor: Fig.onDarkText,
                text: "连接异常，正在重试…"
            )
        } else if isConnectingPanel {
            caption = InterviewPanelCaptionPresentation(
                speakerLabel: "主面试官 · 连接中",
                dotColor: Fig.amber,
                textColor: Fig.onDarkText,
                text: "正在接入面试官，正在同步本场题单…"
            )
        } else if roomSpeaker == .candidate {
            caption = InterviewPanelCaptionPresentation(
                speakerLabel: "你 · 作答中",
                dotColor: Fig.success,
                textColor: Fig.onDarkText,
                text: liveCaptionText.isEmpty ? "等待实时字幕…" : liveCaptionText
            )
        } else {
            caption = InterviewPanelCaptionPresentation(
                speakerLabel: "主面试官 · 提问中",
                dotColor: DeepSpaceTheme.auroraCyan,
                textColor: Fig.onDarkText,
                text: liveCaptionText.isEmpty ? "等待实时字幕…" : liveCaptionText
            )
        }

        bottomHint = ""
        answerControlEnabled = canEnterRoom
    }
}

private struct RedesignInterviewRoomScreen: View {
    @Bindable var session: InterviewSession
    let elapsed: String
    let questionLabel: String
    let dismiss: DismissAction

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .deepSpaceBackground()

            VStack(spacing: 0) {
                RedesignRoomHeader(
                    title: session.entryTitle,
                    elapsed: elapsed,
                    questionLabel: questionLabel,
                    connected: session.connected
                )
                .padding(.top, 8)

                InRoomView(session: session, dismiss: dismiss)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if session.roomPhase == .leaving {
                RedesignLeaveSheet(
                    finish: { Task { await session.finishAndGenerateReview() } },
                    continueInterview: session.continueInterview
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RedesignRoomHeader: View {
    let title: String
    let elapsed: String
    let questionLabel: String
    let connected: Bool

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(Fig.danger)
                    .frame(width: 6, height: 6)
                Text(elapsed)
                    .font(.system(size: 14, weight: .medium))
            }
            Spacer()
            Text("\(title) · \(questionLabel.replacingOccurrences(of: "/", with: " / "))")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Fig.onDarkText.opacity(0.07))
                .clipShape(Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Fig.onDarkText.opacity(0.12), lineWidth: 1))
            Spacer()
            StatusPill(state: connected ? .connected : .connecting)
        }
        .foregroundStyle(Fig.onDarkText)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct InRoomView: View {
    let session: InterviewSession
    let dismiss: DismissAction

    private var presentation: InterviewPanelPresentation {
        InterviewPanelPresentation(session: session)
    }

    var body: some View {
        RoomStageView(
            presentation: presentation,
            requestMicrophone: session.openMicrophoneSettings,
            answerAction: resumeIfPaused,
            leaveAction: leave,
            captionsAction: {},
            onAppear: { session.refreshMicrophonePermission() }
        )
        .animation(.easeInOut(duration: 0.30), value: session.connected)
        .animation(.easeInOut(duration: 0.30), value: session.roomPhase)
        .animation(.easeInOut(duration: 0.30), value: session.microphonePermissionGranted)
    }

    private func resumeIfPaused() {
        guard presentation.answerControlEnabled, session.isPaused else { return }
        Task { await session.resume() }
    }

    private func leave() {
        if session.roomPhase == .connecting {
            Task {
                await session.cancelRoomEntry()
                dismiss()
            }
            return
        }
        if case .failed = session.phase {
            Task {
                await session.leaveIfActive()
                dismiss()
            }
            return
        }
        session.requestLeave()
    }
}

/// 房间舞台纯展示层：真实会话与 DesignGallery 复用同一套布局，保证 1:1 同源。
struct RoomStageView: View {
    let presentation: InterviewPanelPresentation
    var requestMicrophone: () -> Void = {}
    var answerAction: () -> Void = {}
    var leaveAction: () -> Void = {}
    var captionsAction: () -> Void = {}
    var onAppear: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            RoomPanelTiles(presentation: presentation)
                .padding(.top, 14)

            CandidateStrip(presentation: presentation.candidate, requestMicrophone: requestMicrophone)

            LiveCaptionCard(presentation: presentation.caption)

            Spacer()

            HStack(alignment: .top, spacing: 28) {
                ControlButton(kind: .ghost, icon: "captions.bubble", label: "字幕", action: captionsAction)
                ControlButton(
                    kind: .accent,
                    icon: "mic.fill",
                    label: "开口作答",
                    action: answerAction,
                    isEnabled: presentation.answerControlEnabled
                )
                ControlButton(kind: .danger, icon: "arrow.right", label: "离开", action: leaveAction)
            }
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: onAppear)
    }
}

private struct RoomPanelTiles: View {
    let presentation: InterviewPanelPresentation

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(presentation.participantTiles.enumerated()), id: \.offset) { _, participant in
                ParticipantTile(
                    name: participant.name,
                    role: participant.role,
                    state: participant.state,
                    subtitle: participant.subtitle,
                    statusStyleOverride: participant.statusStyle
                )
            }
        }
        .frame(height: 200)
    }
}

private struct CandidateStrip: View {
    let presentation: InterviewPanelCandidatePresentation
    let requestMicrophone: () -> Void

    var body: some View {
        Button(action: requestIfNeeded) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(presentation.isActive ? DeepSpaceTheme.auroraCyan : presentation.statusColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("你 · 候选人")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Fig.onDarkText)
                    Text(presentation.statusText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(presentation.statusColor)
                }
                Spacer()
                if presentation.isActive {
                    MiniWaveBars(color: DeepSpaceTheme.auroraCyan, active: true)
                        .frame(width: 52, height: 28)
                } else if presentation.canRequestMicrophone {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Fig.amber)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 68)
            .glassCard(cornerRadius: 16, strokeOpacity: presentation.isActive ? 0.30 : 0.12)
        }
        .buttonStyle(.plain)
        .disabled(!presentation.canRequestMicrophone)
    }

    private func requestIfNeeded() {
        guard presentation.canRequestMicrophone else { return }
        requestMicrophone()
    }
}

private struct LiveCaptionCard: View {
    let presentation: InterviewPanelCaptionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(presentation.dotColor)
                    .frame(width: 6, height: 6)
                Text(presentation.speakerLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(presentation.dotColor)
                Spacer()
                Text("实时字幕")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Fig.onDarkMuted)
            }
            Text(presentation.text)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(presentation.textColor)
                .lineSpacing(7)
                .lineLimit(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .glassCard(cornerRadius: 18)
    }
}

private struct RedesignLeaveSheet: View {
    let finish: () -> Void
    let continueInterview: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Fig.interviewBackground.opacity(0.78)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Capsule()
                    .fill(Fig.onDarkMuted.opacity(0.52))
                    .frame(width: 40, height: 4)
                Text("离开面试间？")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Fig.onDarkText)
                Text("离开后本场面试将结束，无法回到房间。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Fig.onDarkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button(action: finish) {
                    Text("结束并生成复盘  →")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(DeepSpaceTheme.auroraCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: continueInterview) {
                    Text("继续面试")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Fig.onDarkText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Fig.onDarkText.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fig.onDarkText.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 38)
            .frame(maxWidth: .infinity)
            .background(Fig.interviewElevated)
            .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MiniWaveBars: View {
    let color: Color
    let active: Bool

    private let heights: [CGFloat] = [10, 20, 14, 24, 16]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(active ? 1 : 0.38))
                    .frame(width: 4, height: height)
                    .scaleEffect(y: active ? 1 : 0.88, anchor: .bottom)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.06), value: active)
            }
        }
        .frame(width: 44, height: 28, alignment: .bottom)
    }
}

struct RuntimeDeviceCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            // Fit the 390×844 room design within the SAFE AREA and center it; the dark
            // interview background bleeds to the physical edges for an immersive room.
            let scale = min(1, min(proxy.size.width / 390, proxy.size.height / 844))
            let scaledWidth = 390 * scale
            let scaledHeight = 844 * scale
            ZStack(alignment: .topLeading) {
                content()
            }
            .frame(width: 390, height: 844)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(
                x: max(0, (proxy.size.width - scaledWidth) / 2),
                y: max(0, (proxy.size.height - scaledHeight) / 2)
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Fig.interviewBackground.ignoresSafeArea())
        }
    }
}
