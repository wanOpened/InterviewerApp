import SwiftUI

@MainActor
struct HomeView: View {
    @State private var config: AppConfig
    @State private var agentModel: AgentHomeModel
    @State private var homeVoicePanel: HomeVoicePanelModel
    @State private var schedulePeekModel: HomeSchedulePeekModel
    @State private var session: InterviewSession?
    @State private var isShowingScheduleList = false
    @State private var voiceEditorRoute: HomeVoiceEditorRoute?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let loadedConfig = AppConfig.load()
        let api = Self.makeAPI(loadedConfig)
        let agentModel = AgentHomeModel(api: api)
        let homeVoicePanel = HomeVoicePanelModel(
            api: api,
            liveKit: LiveKitController(),
            liveKitURL: loadedConfig.livekitURL
        )
        let schedulePeekModel = HomeSchedulePeekModel(api: api)
        _config = State(initialValue: loadedConfig)
        _agentModel = State(initialValue: agentModel)
        _homeVoicePanel = State(initialValue: homeVoicePanel)
        _schedulePeekModel = State(initialValue: schedulePeekModel)
    }

    var body: some View {
        ZStack {
            VoiceConciergeHomeScreen(
                state: homeVoicePanel.qinglanState,
                primaryAction: primaryAction,
                primaryActionPresentation: primaryActionPresentation,
                scheduleEntryState: schedulePeekModel.entryState,
                scheduleUpcomingCount: schedulePeekModel.upcomingCount,
                currentTranscript: homeVoicePanel.transcript,
                creationConfirmation: schedulePeekModel.creationConfirmation,
                tapAvatar: handleAvatarTap,
                tapPrimaryAction: handlePrimaryActionTap,
                tapSchedulePeek: handleScheduleEntryTap,
                tapConfirmationViewAll: handleCreationConfirmationViewAll,
                tapConfirmationUndo: handleCreationConfirmationUndo,
                dismissCreationConfirmation: {
                    schedulePeekModel.dismissCreationConfirmation()
                }
            )

            if isShowingScheduleList {
                ScheduleListView(
                    api: Self.makeAPI(config),
                    onClose: { isShowingScheduleList = false },
                    startInterview: { scheduleId in
                        isShowingScheduleList = false
                        enterInterview(.startSchedule(scheduleId: scheduleId))
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            if let voiceEditorRoute {
                HomeVoiceEditorSheetHost(
                    route: voiceEditorRoute,
                    api: Self.makeAPI(config),
                    dismiss: { self.voiceEditorRoute = nil },
                    saved: {
                        self.voiceEditorRoute = nil
                        await agentModel.refresh()
                        await schedulePeekModel.refresh()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .task {
            bindHomeVoiceNavigation()
            await agentModel.refresh()
            await schedulePeekModel.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                Task { await homeVoicePanel.stop() }
            }
        }
        .onChange(of: homeVoicePanel.state) { previous, current in
            guard shouldCheckScheduleCreation(previous: previous, current: current) else { return }
            Task { await schedulePeekModel.refreshAfterVoiceActivity() }
        }
        .fullScreenCover(isPresented: isShowingInterview) {
            if let session {
                InterviewView(
                    session: session,
                    practiceWeakness: { _ in },
                    returnHome: {
                        self.session = nil
                        Task {
                            await agentModel.refresh()
                            await schedulePeekModel.refresh()
                        }
                    }
                )
            }
        }
        .animation(.easeOut(duration: 0.24), value: isShowingScheduleList)
        .animation(.easeOut(duration: 0.24), value: voiceEditorRoute)
    }

    private var isShowingInterview: Binding<Bool> {
        Binding(
            get: { session != nil },
            set: { presented in
                if !presented {
                    session = nil
                }
            }
        )
    }

    private var primaryAction: AgentHomePrimaryAction? {
        homeVoicePanel.currentContext?.primary_action ?? agentModel.recommendation?.primary_action
    }

    private var primaryActionPresentation: HomePrimaryActionPresentation? {
        HomePrimaryActionPresentation.make(action: primaryAction, nextScheduleID: schedulePeekModel.nextSchedule?.id)
    }

    private func bindHomeVoiceNavigation() {
        homeVoicePanel.setNavigateInterviewHandler { sessionId in
            enterInterview(.resume(sessionId: sessionId))
        }
        homeVoicePanel.setOpenEditorHandler { route in
            voiceEditorRoute = route
        }
    }

    private func handleAvatarTap() {
        Task {
            if homeVoicePanel.state == .idle {
                schedulePeekModel.captureCreationSnapshot()
                await homeVoicePanel.start()
            } else {
                await homeVoicePanel.stop()
            }
        }
    }

    private func handlePrimaryActionTap() {
        guard let action = primaryAction else {
            handleAvatarTap()
            return
        }

        switch HomePrimaryActionRouter.route(for: action) {
        case .interview(let launch):
            enterInterview(launch)
        case .voice:
            Task {
                if homeVoicePanel.state == .idle {
                    schedulePeekModel.captureCreationSnapshot()
                }
                await homeVoicePanel.start()
            }
        }
    }

    private func handleScheduleEntryTap() {
        isShowingScheduleList = true
        Task { await homeVoicePanel.stop() }
    }

    private func handleCreationConfirmationViewAll() {
        schedulePeekModel.dismissCreationConfirmation()
        handleScheduleEntryTap()
    }

    private func handleCreationConfirmationUndo() {
        Task { await schedulePeekModel.cancelCreationConfirmation() }
    }

    private func shouldCheckScheduleCreation(previous: HomeVoicePanelState, current: HomeVoicePanelState) -> Bool {
        (previous == .thinking && current != .thinking) || (previous != .idle && current == .idle)
    }

    private func enterInterview(_ launch: HomeInterviewLaunch) {
        Task { await homeVoicePanel.stop() }
        let s = makeSession(title: primaryAction?.title ?? "青岚模拟面试")
        session = s
        Task {
            switch launch {
            case .resume(let sessionId):
                await s.resume(sessionId: sessionId)
            case .startSchedule(let scheduleId):
                await s.start(scheduleId: scheduleId)
            case .startRound(let positionRoundId):
                await s.start(positionRoundId: positionRoundId)
            }
        }
    }

    private func makeSession(title: String) -> InterviewSession {
        let s = InterviewSession(
            config: config,
            api: Self.makeAPI(config),
            liveKit: LiveKitController()
        )
        s.entryTitle = title
        return s
    }

    private static func makeAPI(_ config: AppConfig) -> APIClient {
        APIClient(baseURL: config.apiBaseURL, userExternalId: config.devUserExternalId)
    }
}

private struct HomeVoiceEditorSheetHost: View {
    let route: HomeVoiceEditorRoute
    let api: APIClienting
    let dismiss: () -> Void
    let saved: () async -> Void
    @State private var detail: ScheduleDetailRead?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let detail {
                ScheduleEditSheetView(
                    kind: kind,
                    detail: detail,
                    api: api,
                    dismiss: dismiss,
                    saved: saved
                )
            } else {
                ScheduleDetailPlaceholder(text: errorMessage ?? "正在读取日程")
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.58).ignoresSafeArea())
                    .onTapGesture(perform: dismiss)
            }
        }
        .task(id: scheduleId) {
            await loadDetail()
        }
    }

    private var kind: ScheduleEditKind {
        switch route {
        case .resume:
            return .resume
        case .jd:
            return .jd
        }
    }

    private var scheduleId: String? {
        switch route {
        case .resume(let scheduleId, _), .jd(let scheduleId, _):
            return scheduleId
        }
    }

    private func loadDetail() async {
        guard let scheduleId else {
            errorMessage = "先选择一场面试日程。"
            return
        }
        do {
            detail = try await api.scheduleDetail(id: scheduleId)
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }
}

struct VoiceConciergeHomeScreen: View {
    let state: QinglanState
    let primaryAction: AgentHomePrimaryAction?
    let primaryActionPresentation: HomePrimaryActionPresentation?
    let scheduleEntryState: HomeSchedulePeekEntryState
    let scheduleUpcomingCount: Int
    let currentTranscript: String
    let creationConfirmation: ScheduleCreationConfirmation?
    let tapAvatar: () -> Void
    let tapPrimaryAction: () -> Void
    let tapSchedulePeek: () -> Void
    let tapConfirmationViewAll: () -> Void
    let tapConfirmationUndo: () -> Void
    let dismissCreationConfirmation: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let avatarSize = avatarSize(for: proxy.size)
            let avatarTop = max(120, proxy.size.height * 0.31 - avatarSize / 2)

            ZStack {
                Color.clear
                    .deepSpaceBackground()

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: avatarTop)

                    Button(action: tapAvatar) {
                        QinglanAvatarView(
                            state: state,
                            size: avatarSize
                        )
                        .frame(width: avatarSize, height: avatarSize)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                        .accessibilityIdentifier("home-qinglan-avatar-button")
                        .frame(maxWidth: .infinity)

                    if state == .listening, !currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("“\(currentTranscript)”")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DeepSpaceTheme.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 38)
                            .padding(.top, 42)
                            .transition(.opacity)
                    }

                    Spacer(minLength: 0)

                    SchedulePullChevron(action: tapSchedulePeek)
                        .padding(.bottom, 16)

                    if let primaryActionPresentation {
                        HomePrimaryActionCard(
                            presentation: primaryActionPresentation,
                            actionType: primaryAction?.type ?? "",
                            actionHandler: tapPrimaryAction
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }

                    HomeSchedulePeekHandle(
                        entryState: scheduleEntryState,
                        upcomingCount: scheduleUpcomingCount,
                        action: tapSchedulePeek
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                if let creationConfirmation {
                    ScheduleCreationConfirmationCard(
                        confirmation: creationConfirmation,
                        viewAll: tapConfirmationViewAll,
                        undo: tapConfirmationUndo,
                        dismiss: dismissCreationConfirmation
                    )
                    .padding(.horizontal, 28)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    .padding(.bottom, 188)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .animation(.easeOut(duration: 0.22), value: creationConfirmation)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea(edges: .bottom)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.height < -18 {
                            tapSchedulePeek()
                        }
                    }
            )
        }
    }

    private func avatarSize(for size: CGSize) -> CGFloat {
        min(size.width * 0.58, size.height * 0.46, 320)
    }
}

private struct ScheduleCreationConfirmationCard: View {
    let confirmation: ScheduleCreationConfirmation
    let viewAll: () -> Void
    let undo: () -> Void
    let dismiss: () -> Void
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(DeepSpaceTheme.auroraCyan, lineWidth: 1.2)
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    }
                    .frame(width: 28, height: 28)

                    Text("已为你创建")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.secondaryText)
                        .lineLimit(1)
                }

                Text(confirmation.summary)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 13)

                HStack(spacing: 12) {
                    Button("查看全部", action: viewAll)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 18)
                    Button("撤销", action: undo)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                Spacer(minLength: 0)
            }
            .padding(.top, 19)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(DeepSpaceTheme.auroraCyan)
                    .frame(width: proxy.size.width * progress, height: 3, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
            .clipShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .glassCard(cornerRadius: 20)
        .task(id: confirmation.scheduleID) {
            progress = 1
            withAnimation(.linear(duration: 6)) {
                progress = 0
            }
            do {
                try await Task.sleep(nanoseconds: 6_000_000_000)
                dismiss()
            } catch {}
        }
    }
}

private struct HomeSchedulePeekHandle: View {
    let entryState: HomeSchedulePeekEntryState
    let upcomingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch entryState {
            case .nextSchedule(let label, let secondaryLabel):
                HStack(spacing: 12) {
                    Circle()
                        .fill(DeepSpaceTheme.amber)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DeepSpaceTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if let secondaryLabel {
                            HStack(spacing: 12) {
                                Text(secondaryLabel)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(DeepSpaceTheme.tertiaryText)
                                Capsule(style: .continuous)
                                    .fill(DeepSpaceTheme.auroraCyan)
                                    .frame(width: 92, height: 4)
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                                    .frame(width: 18, height: 4)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 12) {
                        if upcomingCount >= 2 {
                            Text("近期 \(upcomingCount) 场")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DeepSpaceTheme.tertiaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule(style: .continuous))
                        }

                        Text("去准备 ›")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DeepSpaceTheme.auroraCyan)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 92, alignment: .center)
                .glassCard(cornerRadius: 22)
            case .empty:
                HStack(spacing: 12) {
                    Text("日程")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)

                    Spacer()

                    Text("暂无安排")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 56, alignment: .center)
                .glassCard(cornerRadius: 18)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-schedule-peek")
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -8 {
                        action()
                    }
                }
        )
    }
}

/// 双层 120° 上拉箭头：浮在「最重要的事」CTA 上方，轻轻上下浮动，点击进入完整日程层。
/// 对齐 Figma 619:68 H1（节点 662:198 下层 / 665:198 上层）。
private struct SchedulePullChevron: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floats = false

    var body: some View {
        Button(action: action) {
            ZStack {
                chevron(opacity: 0.24, glow: false)
                    .offset(y: -5.5)
                chevron(opacity: 0.5, glow: true)
                    .offset(y: 5.5)
            }
            .frame(width: 30, height: 22)
            .offset(y: reduceMotion ? 0 : (floats ? -4 : 0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: floats
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 44)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-schedule-pull")
        .accessibilityLabel("查看全部日程")
        .onAppear {
            guard !reduceMotion else { return }
            floats = true
        }
        .onChange(of: reduceMotion) { _, newValue in
            floats = !newValue
        }
    }

    private func chevron(opacity: Double, glow: Bool) -> some View {
        UpChevronShape()
            .stroke(
                DeepSpaceTheme.auroraCyan.opacity(opacity),
                style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 30, height: 8.66)
            .shadow(color: glow ? DeepSpaceTheme.auroraCyan.opacity(0.30) : .clear, radius: glow ? 7 : 0)
    }
}

/// 120° 夹角的上扬「人」字形（apex 在顶部中点）。
private struct UpChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct HomePrimaryActionCard: View {
    let presentation: HomePrimaryActionPresentation
    let actionType: String
    let actionHandler: () -> Void

    var body: some View {
        Button(action: actionHandler) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    .frame(width: 24, height: 24)
                    .background(DeepSpaceTheme.auroraCyan.opacity(0.13))
                    .clipShape(Circle())

                Text(presentation.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 10)

                Image(systemName: presentation.accessory)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan.opacity(0.85))
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 56, alignment: .center)
            .glassCard(cornerRadius: 20, strokeOpacity: 0.14)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DeepSpaceTheme.auroraCyan.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch actionType {
        case AgentHomeActionType.reviewResult.rawValue,
             AgentHomeActionType.waitScoring.rawValue:
            return "doc.text.magnifyingglass"
        case AgentHomeActionType.createSchedule.rawValue:
            return "calendar.badge.plus"
        case AgentHomeActionType.addJD.rawValue:
            return "doc.badge.plus"
        case AgentHomeActionType.createTarget.rawValue:
            return "target"
        case AgentHomeActionType.resumeLiveSession.rawValue:
            return "play.fill"
        default:
            return "bolt.fill"
        }
    }
}

struct HomeCTASourceStyle: Equatable {
    let tint: Color

    init(actionType: String) {
        switch actionType {
        case AgentHomeActionType.resumeLiveSession.rawValue,
             AgentHomeActionType.startPractice.rawValue,
             AgentHomeActionType.createSchedule.rawValue,
             AgentHomeActionType.createTarget.rawValue,
             AgentHomeActionType.addJD.rawValue:
            tint = Fig.blue
        case AgentHomeActionType.practiceWeakness.rawValue,
             AgentHomeActionType.quickStart.rawValue:
            tint = Fig.muted
        case AgentHomeActionType.reviewResult.rawValue,
             AgentHomeActionType.waitScoring.rawValue:
            tint = Fig.success
        default:
            tint = Fig.muted
        }
    }
}
