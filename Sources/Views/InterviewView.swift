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
                .ignoresSafeArea()

            // 第二幕 · 面试舞台（深空声场·三幕剧）：保留 v1 房间设计（主面试官 + 你/候选人
            // 同级双卡 + 小牛·面试助手 + 实时字幕 + 字幕/离开），深空皮肤、100% 全屏自适应、
            // 无假状态栏时间。观摩(AI 应聘者)与正式面试(你)共用同一舞台，仅候选人卡不同。
            if session.phase == .finishing {
                ObserveInterviewEndedStage(returnHomeAction: returnHome)
            } else if session.roomMode == .observe {
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(session: session),
                    captionsAction: session.toggleCaptions,
                    leaveAction: observeLeave,
                    captionsVisible: session.captionsVisible
                )
            } else {
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(interviewSession: session),
                    captionsAction: session.toggleCaptions,
                    leaveAction: interviewLeave,
                    requestMicrophone: session.openMicrophoneSettings,
                    captionsVisible: session.captionsVisible
                )
                .onAppear { session.refreshMicrophonePermission() }
            }

            if session.roomMode == .interview, session.roomPhase == .leaving, session.phase != .finishing {
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

    private func interviewLeave() {
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
    let leadStatusDotColor: Color
    let leadStatusTextColor: Color
    let candidateName: String
    let candidateStatus: String
    let noteDotColor: Color
    let captionSpeaker: String
    let captionText: String
    let captionHeight: CGFloat
    let captionFontSize: CGFloat
    let captionFontWeight: Font.Weight
    let captionLineSpacing: CGFloat
    // Candidate-card presentation (shared by 观摩 = "AI 应聘者" and 正式面试 = "你").
    // The live interview reuses this stage with the human as a same-level peer card;
    // `candidateNeedsMicrophone` drives an in-card 点亮麦克风 tap (no bottom 开口作答 button).
    let candidateSubtitle: String
    let candidateActive: Bool
    let candidateStatusDotColor: Color
    let candidateStatusTextColor: Color
    let candidateNeedsMicrophone: Bool

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
        candidateSubtitle = "3 年 · 产品"
        candidateActive = false
        // 候选人卡（观摩=AI 应聘者）恒为 muted：白0.35 点 + 白0.55 字（Figma 632/633）。
        candidateStatusDotColor = Color.white.opacity(0.35)
        candidateStatusTextColor = Color.white.opacity(0.55)
        candidateNeedsMicrophone = false

        if connecting {
            state = .connecting
            leadStatus = "接入中"
            // 接入态：主面试官点=青（品牌锚点），文字=白0.55（尚未开口）。
            leadStatusDotColor = DeepSpaceTheme.auroraCyan
            leadStatusTextColor = Color.white.opacity(0.55)
            candidateName = "你"
            candidateStatus = "待接入"
            noteDotColor = DeepSpaceTheme.amber
            captionSpeaker = "主面试官 · 连接中"
            captionText = "正在接入面试官，正在同步本场题单…"
            captionHeight = 132
            captionFontSize = 17
            captionFontWeight = .regular
            captionLineSpacing = 6
        } else {
            state = .live
            leadStatus = "在提问"
            // 在提问：主面试官点+字皆青（Figma 633）。
            leadStatusDotColor = DeepSpaceTheme.auroraCyan
            leadStatusTextColor = DeepSpaceTheme.auroraCyan
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

    /// 正式面试：复用同一座 第二幕·面试舞台，候选人卡是「你 · 候选人」同级 peer。
    /// 与观摩(AI 应聘者)唯一的差别是候选人卡的名字/状态，以及未授权麦克风时
    /// 卡片可点击调起系统设置(`candidateNeedsMicrophone`)，没有底部「开口作答」按钮。
    @MainActor
    init(interviewSession session: InterviewSession) {
        let connecting = !session.connected || session.roomPhase == .connecting
        let index = max(1, session.currentQuestionIndex)
        let total = session.totalQuestions > 0 ? session.totalQuestions : 6
        let title = session.entryTitle.isEmpty ? "字节终面" : session.entryTitle

        headerTitle = "\(title) · Q \(index) / \(total)"
        isConnected = session.connected && !connecting
        connectionLabel = isConnected ? "已连接" : "连接中"
        candidateName = "你"
        candidateSubtitle = "候选人"

        let candidateSpeaking = session.roomSpeaker == .candidate && !connecting

        if connecting {
            state = .connecting
            leadStatus = "接入中"
            leadStatusDotColor = DeepSpaceTheme.auroraCyan
            leadStatusTextColor = Color.white.opacity(0.55)
            candidateStatus = "待接入"
            candidateStatusDotColor = Color.white.opacity(0.35)
            candidateStatusTextColor = Color.white.opacity(0.55)
            candidateActive = false
            candidateNeedsMicrophone = false
            noteDotColor = DeepSpaceTheme.amber
            captionSpeaker = "主面试官 · 连接中"
            captionText = "正在接入面试官，正在同步本场题单…"
            captionHeight = 132
            captionFontSize = 17
            captionFontWeight = .regular
            captionLineSpacing = 6
        } else {
            state = .live
            leadStatus = candidateSpeaking ? "聆听中" : "在提问"
            // 主面试官是青色锚点卡，状态点+字皆青（Figma 633）。
            leadStatusDotColor = DeepSpaceTheme.auroraCyan
            leadStatusTextColor = DeepSpaceTheme.auroraCyan
            noteDotColor = DeepSpaceTheme.reviewGreen
            if !session.microphonePermissionGranted {
                // 麦克风未授权（设计稿外的运行态）：用深空琥珀做「待办」提示，非旧脏橙。
                candidateStatus = "开启麦克风"
                candidateStatusDotColor = DeepSpaceTheme.amber
                candidateStatusTextColor = DeepSpaceTheme.amber
                candidateActive = false
                candidateNeedsMicrophone = true
            } else if candidateSpeaking {
                candidateStatus = "作答中"
                candidateStatusDotColor = DeepSpaceTheme.auroraCyan
                candidateStatusTextColor = DeepSpaceTheme.auroraCyan
                candidateActive = true
                candidateNeedsMicrophone = false
            } else {
                candidateStatus = "聆听中"
                candidateStatusDotColor = Color.white.opacity(0.35)
                candidateStatusTextColor = Color.white.opacity(0.55)
                candidateActive = false
                candidateNeedsMicrophone = false
            }
            captionSpeaker = candidateSpeaking ? "你 · 作答中" : "主面试官 · 提问中"
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
        leadStatusDotColor: Color,
        leadStatusTextColor: Color,
        candidateName: String,
        candidateStatus: String,
        noteDotColor: Color,
        captionSpeaker: String,
        captionText: String,
        captionHeight: CGFloat,
        captionFontSize: CGFloat,
        captionFontWeight: Font.Weight,
        captionLineSpacing: CGFloat,
        candidateSubtitle: String = "3 年 · 产品",
        candidateActive: Bool = false,
        candidateStatusDotColor: Color = Color.white.opacity(0.35),
        candidateStatusTextColor: Color = Color.white.opacity(0.55),
        candidateNeedsMicrophone: Bool = false
    ) {
        self.state = state
        self.headerTitle = headerTitle
        self.connectionLabel = connectionLabel
        self.isConnected = isConnected
        self.leadStatus = leadStatus
        self.leadStatusDotColor = leadStatusDotColor
        self.leadStatusTextColor = leadStatusTextColor
        self.candidateName = candidateName
        self.candidateStatus = candidateStatus
        self.noteDotColor = noteDotColor
        self.captionSpeaker = captionSpeaker
        self.captionText = captionText
        self.captionHeight = captionHeight
        self.captionFontSize = captionFontSize
        self.captionFontWeight = captionFontWeight
        self.captionLineSpacing = captionLineSpacing
        self.candidateSubtitle = candidateSubtitle
        self.candidateActive = candidateActive
        self.candidateStatusDotColor = candidateStatusDotColor
        self.candidateStatusTextColor = candidateStatusTextColor
        self.candidateNeedsMicrophone = candidateNeedsMicrophone
    }
}

struct ObserveInterviewStage: View {
    let presentation: ObserveInterviewStagePresentation
    let captionsAction: () -> Void
    let leaveAction: () -> Void
    var requestMicrophone: (() -> Void)? = nil
    var captionsVisible: Bool = true

    var body: some View {
        ZStack {
            ObserveStageBackground()
                .ignoresSafeArea()

            // 业务内容从安全区域内开始布局：背景铺满整屏，内容由 VStack 自适应排版，
            // 顶部留 6pt（设计稿 header 距状态栏 ~6pt），系统状态栏/Home Indicator 由 iOS 提供。
            VStack(spacing: 0) {
                header

                HStack(spacing: 12) {
                    ObserveParticipantCard(
                        name: "主面试官",
                        subtitle: "产品方向",
                        status: presentation.leadStatus,
                        statusDotColor: presentation.leadStatusDotColor,
                        statusTextColor: presentation.leadStatusTextColor,
                        highlight: presentation.state == .live ? .speaking : .connecting
                    )
                    ObserveParticipantCard(
                        name: presentation.candidateName,
                        subtitle: presentation.candidateSubtitle,
                        status: presentation.candidateStatus,
                        statusDotColor: presentation.candidateStatusDotColor,
                        statusTextColor: presentation.candidateStatusTextColor,
                        highlight: presentation.candidateActive ? .speaking : .none,
                        tapAction: presentation.candidateNeedsMicrophone ? requestMicrophone : nil
                    )
                }
                .padding(.top, 22)

                ObserveAssistantRow(dotColor: presentation.noteDotColor)
                    .padding(.top, 16)

                if captionsVisible {
                    ObserveCaptionCard(presentation: presentation)
                        .padding(.top, 20)
                }

                Spacer(minLength: 20)

                ObserveBottomControls(
                    captionsOn: captionsVisible,
                    captionsAction: captionsAction,
                    leaveAction: leaveAction
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        ZStack {
            Text(presentation.headerTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                ObserveConnectionBadge(
                    text: presentation.connectionLabel,
                    connected: presentation.isConnected
                )
            }
        }
        .frame(height: 22)
    }
}

private struct ObserveStageBackground: View {
    var body: some View {
        // 深空底（样式板 642:72）：#05070D → #0B1222
        LinearGradient(
            colors: [
                DeepSpaceTheme.color(0x05070D),
                DeepSpaceTheme.color(0x0B1222),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ObserveConnectionBadge: View {
    let text: String
    let connected: Bool

    var body: some View {
        if connected {
            // 已连接（S2 651:122/123）：绿点 + 浅灰文字
            HStack(spacing: 6) {
                Circle()
                    .fill(DeepSpaceTheme.reviewGreen)
                    .frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        } else {
            // 连接中（S1 650:122）：青色玻璃胶囊（51×22）
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DeepSpaceTheme.auroraCyan)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(DeepSpaceTheme.auroraCyan.opacity(0.16))
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DeepSpaceTheme.auroraCyan.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

private struct ObserveParticipantCard: View {
    enum Highlight { case none, connecting, speaking }

    let name: String
    let subtitle: String
    let status: String
    let statusDotColor: Color
    let statusTextColor: Color
    let highlight: Highlight
    var tapAction: (() -> Void)? = nil

    var body: some View {
        if let tapAction {
            Button(action: tapAction) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        // 玻璃卡（169×196 @ 设计稿）：头像 → 姓名 → 副标题 → 状态点+文字，竖向自适应；
        // 卡宽改为填充，双卡 12pt 间距在 350pt 内容区内还原为 169；更宽屏等比拉伸。
        VStack(spacing: 0) {
            ObservePersonAvatar(size: 72, highlight: highlight)
                .padding(.top, 34)

            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(nameOpacity))
                .padding(.top, 12)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 5)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(statusTextColor)
            }
            .padding(.top, 11)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
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

    private var nameOpacity: Double {
        switch highlight {
        case .speaking: 0.95
        case .connecting: 0.92
        case .none: 0.80
        }
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
        // 小牛·面试助手行（350×64 @ 设计稿）：头像 + 姓名/状态，横向自适应填充。
        HStack(spacing: 8) {
            ObservePersonAvatar(size: 40, highlight: .none)

            VStack(alignment: .leading, spacing: 4) {
                Text("小牛· 面试助手")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))

                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text("记笔记中")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
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
        // 实时字幕卡（350×188 进行中 / 132 接入中 @ 设计稿）：标题行 + 字幕正文，
        // 固定卡高、内容顶对齐，横向自适应填充。
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DeepSpaceTheme.auroraCyan)
                    .frame(width: 7, height: 7)
                Text(presentation.captionSpeaker)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan.opacity(0.95))
                Spacer(minLength: 8)
                Text("实时字幕")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.40))
            }

            captionBody
                .font(.system(size: presentation.captionFontSize, weight: presentation.captionFontWeight))
                .foregroundStyle(Color.white.opacity(presentation.state == .live ? 0.95 : 0.85))
                .lineSpacing(presentation.captionLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
        .frame(maxWidth: .infinity)
        .frame(height: presentation.captionHeight)
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
    var captionsOn: Bool = true
    let captionsAction: () -> Void
    let leaveAction: () -> Void

    var body: some View {
        // 底部控制（cc 52,724 / → 282,724 @ 设计稿）：左 cc·字幕、右 →·离开，
        // 各内缩 40pt（外层 20 + 此处 20），中间留白由 Spacer 撑开。
        HStack(alignment: .top, spacing: 0) {
            controlItem(label: "字幕", action: captionsAction) {
                Text("cc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(captionsOn ? 0.75 : 0.35))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(captionsOn ? 0.08 : 0.04))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(captionsOn ? 0.16 : 0.10), lineWidth: 1))
            }

            Spacer(minLength: 0)

            controlItem(label: "离开", action: leaveAction) {
                Text("→")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DeepSpaceTheme.dangerText)
                    .frame(width: 56, height: 56)
                    .background(Color(red: 1, green: 89 / 255, blue: 102 / 255).opacity(0.14))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(red: 1, green: 115 / 255, blue: 128 / 255).opacity(0.45), lineWidth: 1))
            }
        }
        // 叠加外层 20pt → cc 左缘 52pt、→ 右缘距右 52pt（对齐设计稿 52,724 / 282,724）。
        .padding(.horizontal, 32)
    }

    private func controlItem<Content: View>(
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            Button(action: action) { content() }
                .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.50))
        }
    }
}

struct ObserveInterviewEndedStage: View {
    let returnHomeAction: () -> Void

    var body: some View {
        // S3 收尾（634:70）：声场收束 + 「本场面试已结束」+ 生成中胶囊 + 回到首页。
        // 居中式 hero，竖向自适应；无假状态栏时间，系统 UI 由 iOS 提供。
        ZStack {
            ObserveStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    ObserveQinglanHalo()
                    CompanionAvatarArt(companion: .qinglan, state: .idle)
                        .frame(width: 132, height: 165)
                }

                Text("本场面试已结束")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.top, 48)

                Text("小牛正在生成复盘 · 约 2 分钟")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(DeepSpaceTheme.auroraCyan.opacity(0.14))
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DeepSpaceTheme.auroraCyan.opacity(0.40), lineWidth: 1)
                    )
                    .padding(.top, 16)

                Spacer()

                Button(action: returnHomeAction) {
                    Text("回到首页")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 27, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ObserveQinglanHalo: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.08), lineWidth: 1)
                .frame(width: 242, height: 242)

            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.12), lineWidth: 1)
                .frame(width: 198, height: 198)

            Circle()
                .fill(DeepSpaceTheme.auroraCyan.opacity(0.10))
                .blur(radius: 40)
                .frame(width: 187, height: 187)

            Circle()
                .stroke(DeepSpaceTheme.auroraCyan.opacity(0.18), lineWidth: 1)
                .frame(width: 154, height: 154)
        }
        .frame(width: 242, height: 242)
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
