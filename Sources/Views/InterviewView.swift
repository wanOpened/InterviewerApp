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
                        dismiss: dismiss,
                        returnHome: returnHome
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
    let returnHome: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .deepSpaceBackground()

            if session.roomMode == .observe {
                RuntimeDeviceCanvas {
                    if session.phase == .finishing {
                        ObserveInterviewEndedStage(returnHomeAction: returnHome)
                    } else {
                        ObserveInterviewStage(
                            presentation: ObserveInterviewStagePresentation(session: session),
                            captionsAction: {},
                            leaveAction: observeLeave
                        )
                    }
                }
            } else {
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
            }

            if session.roomMode == .interview, session.roomPhase == .leaving {
                RedesignLeaveSheet(
                    finish: { Task { await session.finishAndGenerateReview() } },
                    continueInterview: session.continueInterview
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func observeLeave() {
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
        Task { await session.end() }
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

enum ObserveStageState: Equatable {
    case connecting
    case live
}

struct ObserveInterviewStagePresentation: Equatable {
    let state: ObserveStageState
    let headerTitle: String
    let connectionLabel: String
    let isConnected: Bool
    let leadStatus: String
    let leadStatusColor: Color
    let candidateName: String
    let candidateStatus: String
    let noteDotColor: Color
    let captionSpeaker: String
    let captionText: String
    let captionHeight: CGFloat
    let captionFontSize: CGFloat
    let captionFontWeight: Font.Weight
    let captionLineSpacing: CGFloat

    @MainActor
    init(session: InterviewSession) {
        let connecting = !session.connected
        let index = max(1, session.currentQuestionIndex)
        let total = session.totalQuestions > 0 ? session.totalQuestions : 6
        let title = session.entryTitle.isEmpty ? "字节终面" : session.entryTitle
        let questionLabel = "Q \(index) / \(total)"

        headerTitle = "\(title) · \(questionLabel)"
        isConnected = session.connected && !connecting
        connectionLabel = isConnected ? "已连接" : "连接中"

        if connecting {
            state = .connecting
            leadStatus = "接入中"
            leadStatusColor = Fig.onDarkMuted
            candidateName = "你"
            candidateStatus = "待接入"
            noteDotColor = Fig.amber
            captionSpeaker = "主面试官 · 连接中"
            captionText = "正在接入面试官，正在同步本场题单…"
            captionHeight = 132
            captionFontSize = 17
            captionFontWeight = .regular
            captionLineSpacing = 6
        } else {
            state = .live
            leadStatus = "在提问"
            leadStatusColor = DeepSpaceTheme.auroraCyan
            candidateName = "AI 应聘者"
            candidateStatus = "待作答"
            noteDotColor = DeepSpaceTheme.reviewGreen
            captionSpeaker = session.roomSpeaker == .candidate ? "AI 应聘者 · 作答中" : "主面试官 · 提问中"
            captionText = session.liveCaptionText.isEmpty
                ? "先用一分钟介绍你最近主导的产品，重点说说你当时的判断依据。"
                : session.liveCaptionText
            captionHeight = 188
            captionFontSize = 19
            captionFontWeight = .medium
            captionLineSpacing = 8
        }
    }

    /// Memberwise init — lets the dev-only DesignGallery drive the 第二幕 frames
    /// (S1/S2/S3) with sample data so they screenshot 1:1 against Figma 632/633,
    /// reusing the exact production `ObserveInterviewStage` layout (single source).
    init(
        state: ObserveStageState,
        headerTitle: String,
        connectionLabel: String,
        isConnected: Bool,
        leadStatus: String,
        leadStatusColor: Color,
        candidateName: String,
        candidateStatus: String,
        noteDotColor: Color,
        captionSpeaker: String,
        captionText: String,
        captionHeight: CGFloat,
        captionFontSize: CGFloat,
        captionFontWeight: Font.Weight,
        captionLineSpacing: CGFloat
    ) {
        self.state = state
        self.headerTitle = headerTitle
        self.connectionLabel = connectionLabel
        self.isConnected = isConnected
        self.leadStatus = leadStatus
        self.leadStatusColor = leadStatusColor
        self.candidateName = candidateName
        self.candidateStatus = candidateStatus
        self.noteDotColor = noteDotColor
        self.captionSpeaker = captionSpeaker
        self.captionText = captionText
        self.captionHeight = captionHeight
        self.captionFontSize = captionFontSize
        self.captionFontWeight = captionFontWeight
        self.captionLineSpacing = captionLineSpacing
    }
}

struct ObserveInterviewStage: View {
    let presentation: ObserveInterviewStagePresentation
    let captionsAction: () -> Void
    let leaveAction: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ObserveStageBackground()

            Text("9:41")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .observeFrame(x: 30, y: 16, width: 32, height: 18, alignment: .leading)

            Text(presentation.headerTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .multilineTextAlignment(.center)
                .observeFrame(x: 0, y: 54, width: 390, height: 18)

            ObserveConnectionBadge(
                text: presentation.connectionLabel,
                connected: presentation.isConnected
            )

            ObserveParticipantCard(
                name: "主面试官",
                subtitle: "产品方向",
                status: presentation.leadStatus,
                statusColor: presentation.leadStatusColor,
                highlight: presentation.state == .live ? .speaking : .connecting
            )
            .observeFrame(x: 20, y: 96, width: 169, height: 196)

            ObserveParticipantCard(
                name: presentation.candidateName,
                subtitle: "3 年 · 产品",
                status: presentation.candidateStatus,
                statusColor: Fig.onDarkMuted,
                highlight: .none
            )
            .observeFrame(x: 201, y: 96, width: 169, height: 196)

            ObserveAssistantRow(dotColor: presentation.noteDotColor)
                .observeFrame(x: 20, y: 308, width: 350, height: 64)

            ObserveCaptionCard(presentation: presentation)
                .observeFrame(x: 20, y: 392, width: 350, height: presentation.captionHeight)

            ObserveBottomControls(
                captionsAction: captionsAction,
                leaveAction: leaveAction
            )
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ObserveStageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                DeepSpaceTheme.color(0x04050B),
                DeepSpaceTheme.color(0x0C1224),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 390, height: 844)
    }
}

private struct ObserveConnectionBadge: View {
    let text: String
    let connected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if connected {
                Circle()
                    .fill(DeepSpaceTheme.reviewGreen)
                    .frame(width: 6, height: 6)
                    .observeFrame(x: 320, y: 60, width: 6, height: 6)

                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .observeFrame(x: 332, y: 56, width: 33, height: 13, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    .frame(width: 51, height: 22)
                    .background(DeepSpaceTheme.auroraCyan.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DeepSpaceTheme.auroraCyan.opacity(0.45), lineWidth: 1)
                    )
                    .observeFrame(x: 319, y: 52, width: 51, height: 22)
            }
        }
        .frame(width: 390, height: 844)
    }
}

private struct ObserveParticipantCard: View {
    enum Highlight { case none, connecting, speaking }

    let name: String
    let subtitle: String
    let status: String
    let statusColor: Color
    let highlight: Highlight

    var body: some View {
        ZStack(alignment: .topLeading) {
            ObservePersonAvatar(size: 72, highlight: highlight)
                .observeFrame(x: avatarX, y: avatarY, width: 72, height: 72)

            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(nameOpacity))
                .multilineTextAlignment(.center)
                .observeFrame(x: 0, y: titleY, width: 169, height: 17)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .observeFrame(x: 0, y: subtitleY, width: 169, height: 13)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .observeFrame(x: statusDotX, y: statusDotY, width: 6, height: 6)

            Text(status)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(statusColor)
                .observeFrame(x: statusTextX, y: statusTextY, width: 33, height: 13, alignment: .leading)
        }
        .frame(width: 169, height: 196)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    borderColor,
                    lineWidth: borderWidth
                )
        )
        .shadow(color: cardShadowColor, radius: 30)
    }

    private var avatarX: CGFloat {
        48.5
    }

    private var avatarY: CGFloat {
        34
    }

    private var titleY: CGFloat {
        118
    }

    private var subtitleY: CGFloat {
        140
    }

    private var nameOpacity: Double {
        switch highlight {
        case .speaking: 0.95
        case .connecting: 0.92
        case .none: 0.80
        }
    }

    private var statusDotX: CGFloat {
        switch highlight {
        case .speaking: 58
        case .connecting: 58
        case .none: status == "待作答" ? 62 : 58
        }
    }

    private var statusTextX: CGFloat {
        switch highlight {
        case .speaking: 70
        case .connecting: 70
        case .none: status == "待作答" ? 74 : 70
        }
    }

    private var statusDotY: CGFloat {
        168
    }

    private var statusTextY: CGFloat {
        164
    }

    private var borderColor: Color {
        switch highlight {
        case .speaking: DeepSpaceTheme.auroraCyan.opacity(0.65)
        case .connecting: DeepSpaceTheme.auroraCyan.opacity(0.40)
        case .none: Color.white.opacity(0.12)
        }
    }

    private var borderWidth: CGFloat {
        highlight == .speaking ? 1.5 : 1
    }

    private var cardShadowColor: Color {
        highlight == .speaking ? DeepSpaceTheme.auroraCyan.opacity(0.25) : .clear
    }
}

private struct ObservePersonAvatar: View {
    let size: CGFloat
    let highlight: ObserveParticipantCard.Highlight

    var body: some View {
        ZStack {
            if highlight == .speaking {
                Circle()
                    .stroke(DeepSpaceTheme.auroraCyan.opacity(0.35), lineWidth: 1.5)
                    .frame(width: size + 16, height: size + 16)
            }

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(y: -size * 0.12)
                Ellipse()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: size * 0.66, height: size * 0.50)
                    .offset(y: size * 0.37)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        highlight == .none
                            ? Color.white.opacity(0.18)
                            : DeepSpaceTheme.auroraCyan.opacity(0.70),
                        lineWidth: highlight == .none ? 1 : 1.5
                    )
            )
        }
        .frame(width: size, height: size)
        .shadow(color: highlight == .none ? .clear : DeepSpaceTheme.auroraCyan.opacity(0.35), radius: 12)
    }
}

private struct ObserveAssistantRow: View {
    let dotColor: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            ObservePersonAvatar(size: 40, highlight: .none)
                .observeFrame(x: 16, y: 12, width: 40, height: 40)

            Text("小牛· 面试助手")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .observeFrame(x: 64, y: 13, width: 102, height: 17, alignment: .leading)

            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .observeFrame(x: 64, y: 41, width: 6, height: 6)

            Text("记笔记中")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
                .observeFrame(x: 76, y: 37, width: 44, height: 13, alignment: .leading)
        }
        .frame(width: 350, height: 64)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ObserveCaptionCard: View {
    let presentation: ObserveInterviewStagePresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(DeepSpaceTheme.auroraCyan)
                .frame(width: 7, height: 7)
                .observeFrame(x: 20, y: 23, width: 7, height: 7)

            Text(presentation.captionSpeaker)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeepSpaceTheme.auroraCyan.opacity(0.95))
                .observeFrame(x: 36, y: 17, width: 170, height: 20, alignment: .leading)

            Text("实时字幕")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.40))
                .observeFrame(x: 282, y: 19, width: 50, height: 18, alignment: .leading)

            captionBody
                .font(.system(size: presentation.captionFontSize, weight: presentation.captionFontWeight))
                .foregroundStyle(Color.white.opacity(presentation.state == .live ? 0.95 : 0.85))
                .lineSpacing(presentation.captionLineSpacing)
                .observeFrame(
                    x: 20,
                    y: 52,
                    width: 310,
                    height: presentation.state == .live ? 68 : max(64, presentation.captionHeight - 64),
                    alignment: .topLeading
                )
        }
        .frame(width: 350, height: presentation.captionHeight)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var captionBody: Text {
        let text = presentation.captionText
        guard presentation.state == .live,
              let range = text.range(of: "判断依据")
        else { return Text(text) }

        let before = String(text[..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])
        return Text(before)
            + Text(match).foregroundColor(DeepSpaceTheme.auroraCyan)
            + Text(after)
    }
}

private struct ObserveBottomControls: View {
    let captionsAction: () -> Void
    let leaveAction: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: captionsAction) {
                Text("cc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .observeFrame(x: 52, y: 724, width: 56, height: 56)

            Text("字幕")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.50))
                .multilineTextAlignment(.center)
                .observeFrame(x: 40, y: 786, width: 80, height: 13)

            Button(action: leaveAction) {
                Text("→")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DeepSpaceTheme.dangerText)
                    .frame(width: 56, height: 56)
                    .background(Color(red: 1, green: 89 / 255, blue: 102 / 255).opacity(0.14))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(red: 1, green: 115 / 255, blue: 128 / 255).opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .observeFrame(x: 282, y: 724, width: 56, height: 56)

            Text("离开")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.50))
                .multilineTextAlignment(.center)
                .observeFrame(x: 270, y: 786, width: 80, height: 13)
        }
        .frame(width: 390, height: 844)
    }
}

struct ObserveInterviewEndedStage: View {
    let returnHomeAction: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ObserveStageBackground()

            Text("9:41")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .observeFrame(x: 30, y: 16, width: 32, height: 18, alignment: .leading)

            ObserveQinglanHalo()

            CompanionAvatarArt(companion: .qinglan, state: .idle)
                .observeFrame(x: 129, y: 218, width: 132, height: 165)

            Text("本场面试已结束")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .observeFrame(x: 0, y: 470, width: 390, height: 34)

            Text("小牛正在生成复盘 · 约 2 分钟")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeepSpaceTheme.auroraCyan)
                .frame(width: 165, height: 28)
                .background(DeepSpaceTheme.auroraCyan.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DeepSpaceTheme.auroraCyan.opacity(0.40), lineWidth: 1)
                )
                .observeFrame(x: 112.5, y: 520, width: 165, height: 28)

            Button(action: returnHomeAction) {
                Text("回到首页")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .frame(width: 350, height: 54)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .observeFrame(x: 20, y: 700, width: 350, height: 54)
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ObserveQinglanHalo: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.08), lineWidth: 1)
                .frame(width: 242, height: 242)
                .observeFrame(x: 74, y: 179, width: 242, height: 242)

            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.12), lineWidth: 1)
                .frame(width: 198, height: 198)
                .observeFrame(x: 96, y: 201, width: 198, height: 198)

            Circle()
                .fill(DeepSpaceTheme.auroraCyan.opacity(0.10))
                .blur(radius: 40)
                .observeFrame(x: 101.5, y: 206.5, width: 187, height: 187)

            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.18), lineWidth: 1)
                .frame(width: 154, height: 154)
                .observeFrame(x: 118, y: 223, width: 154, height: 154)
        }
        .frame(width: 390, height: 844)
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

private extension View {
    func observeFrame(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        frame(width: width, height: height, alignment: alignment)
            .position(x: x + width / 2, y: y + height / 2)
    }
}
