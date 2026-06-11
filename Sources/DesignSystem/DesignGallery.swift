import SwiftUI

/// Dev-only 设计审查画廊。通过 launch argument `-DesignGallery` 或环境变量
/// `DESIGN_GALLERY=1` 进入，用样例数据渲染各屏各态，供模拟器截图逐帧对比 Figma 619:68。
/// 不进入正式发布流程（仅在带该参数启动时替换根视图）。
enum DesignGalleryGate {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-DesignGallery") { return true }
        return ProcessInfo.processInfo.environment["DESIGN_GALLERY"] == "1"
    }

    /// 用 `-DesignGalleryScreen <name>` 指定单屏，便于逐屏满帧截图。
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-DesignGalleryScreen"), idx + 1 < args.count else {
            return ProcessInfo.processInfo.environment["DESIGN_GALLERY_SCREEN"]
        }
        return args[idx + 1]
    }
}

struct DesignGalleryRootView: View {
    var body: some View {
        switch DesignGalleryGate.screen {
        case "qinglan":
            QinglanStatesGallery()
        case "home-idle":
            GalleryHomeScreen(state: .idle)
        case "home-listening":
            GalleryHomeScreen(state: .listening, transcript: "帮我约周四晚上字节的三面")
        case "home-thinking":
            GalleryHomeScreen(state: .thinking)
        case "home-speaking":
            GalleryHomeScreen(state: .speaking)
        case "home-confirm":
            GalleryHomeScreen(
                state: .speaking,
                confirmation: ScheduleCreationConfirmation(scheduleID: "demo", summary: "周四 20:00 · 字节 · 三面")
            )
        case "report":
            ReportView(result: DesignGallerySamples.report, context: DesignGallerySamples.reportContext)
        case "schedule-list":
            ScheduleListView(api: GalleryFakeAPI())
        case "schedule-detail":
            ScheduleDetailView(scheduleId: DesignGallerySamples.nextScheduleID, api: GalleryFakeAPI())
        case "schedule-edit-jd":
            ZStack {
                Color.clear.deepSpaceBackground()
                ScheduleEditSheetView(kind: .jd, detail: DesignGallerySamples.scheduleDetail, api: GalleryFakeAPI(), dismiss: {}, saved: {})
            }
        case "interview-s1":
            GalleryInterviewS1()
        case "interview-s2":
            GalleryInterviewS2()
        case "interview-s3":
            DoneView(
                sessionId: "demo",
                companion: .qinglan,
                loadResult: {
                    try await Task.sleep(nanoseconds: 600_000_000_000)
                    return DesignGallerySamples.report
                },
                practiceWeakness: { _ in },
                returnHome: {}
            )
        default:
            QinglanStatesGallery()
        }
    }
}

/// 样例数据（对齐 Figma R1-R3 报告三帧）。
enum DesignGallerySamples {
    static let reportContext = ReportContext(
        company: "字节", round: "终面", dateText: "6 月 9 日", durationText: "28 分钟"
    )

    static var report: SessionResultRead {
        SessionResultRead(
            session_id: "demo",
            overall_score: 78,
            dimension_scores: [:],
            dimensions: [
                DimensionScoreRead(key: "structure", label: "结构化表达", score: 82, is_weakest: false),
                DimensionScoreRead(key: "insight", label: "业务洞察", score: 74, is_weakest: false),
                DimensionScoreRead(key: "data", label: "数据思维", score: 71, is_weakest: true),
                DimensionScoreRead(key: "empathy", label: "用户同理心", score: 80, is_weakest: false),
                DimensionScoreRead(key: "reaction", label: "临场反应", score: 76, is_weakest: false),
            ],
            weakest_dimension: "data",
            per_question_review: [
                [
                    "question": .string("如果你负责的产品 DAU 一个月内腰斩，你会怎么定位问题？"),
                    "score": .string("13 / 20"),
                    "answer": .string("结构清晰，先内因后外因；但缺少数据假设与验证顺序。"),
                    "better_answer": .string("先按新老用户 × 渠道 × 版本三轴分层，锁定跌幅集中段后再提假设。"),
                ],
                [
                    "question": .string("给老年用户做内容产品，你会怎么定义北极星指标？"),
                    "score": .string("16 / 20"),
                    "answer": .string("提出「周均有效陪伴时长」，并主动给出反作弊口径，是本场亮点。"),
                ],
                [
                    "question": .string("如何评估一个新功能要不要做？"),
                    "score": .string("11 / 20"),
                ],
            ],
            coaching_plan: [
                "items": .array([
                    .object([
                        "title": .string("数据思维 · 漏斗拆解专项"),
                        "subtitle": .string("针对 Q1 的分层定位短板"),
                        "duration": .string("15 分钟"),
                    ]),
                    .object([
                        "title": .string("STAR 结构表达训练"),
                        "subtitle": .string("回答收尾偏弱，练结论前置"),
                        "duration": .string("10 分钟"),
                    ]),
                    .object([
                        "title": .string("字节业务追问模拟"),
                        "subtitle": .string("高压追问下的临场反应"),
                        "duration": .string("20 分钟"),
                    ]),
                ]),
            ],
            is_partial: false
        )
    }

    // MARK: 日程样例（H3/H4/H5，对齐 Figma 625/626/629）
    static let nextScheduleID = "demo-bytedance"

    static func iso(daysFromNow: Int, hour: Int, minute: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let base = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: base) ?? base
        let dt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: dt)
    }

    static var schedules: [InterviewScheduleRead] {
        [
            InterviewScheduleRead(
                id: nextScheduleID, position_round_id: "pr1",
                scheduled_at: iso(daysFromNow: 1, hour: 14), timezone: "Asia/Shanghai",
                duration_minutes: 30, status: "scheduled", session_id: nil,
                raw_command: "帮我约明天下午两点字节前端终面", created_at: iso(daysFromNow: 0, hour: 9),
                position_title: "前端终面", company: "字节跳动", round_name: "前端终面"
            ),
            InterviewScheduleRead(
                id: "demo-ant", position_round_id: "pr2",
                scheduled_at: iso(daysFromNow: 3, hour: 10), timezone: "Asia/Shanghai",
                duration_minutes: 30, status: "scheduled", session_id: nil,
                raw_command: "约周六上午蚂蚁产品二面", created_at: iso(daysFromNow: 0, hour: 9),
                position_title: "产品二面", company: "蚂蚁", round_name: "产品二面"
            ),
            InterviewScheduleRead(
                id: "demo-rednote", position_round_id: "pr3",
                scheduled_at: iso(daysFromNow: -8, hour: 10), timezone: "Asia/Shanghai",
                duration_minutes: 30, status: "ended", session_id: "demo",
                raw_command: "小红书内容策略一面", created_at: iso(daysFromNow: -10, hour: 9),
                position_title: "内容策略一面", company: "小红书", round_name: "内容策略一面"
            ),
        ]
    }

    static let position = PositionRead(
        id: "pos1", title: "前端终面", company: "字节跳动",
        jd_text: "负责字节核心产品的前端架构与性能优化；要求 5 年以上前端经验，精通 React 生态、工程化与跨端方案；有大型团队协作与技术决策经验，能主导复杂项目落地。",
        seniority: "终面", created_at: iso(daysFromNow: -2, hour: 9)
    )

    static let resume = ResumeRead(
        id: "res1", version: 3, is_current: true,
        raw_text: "（示例简历）5 年前端经验，主导多个大型项目的架构与性能优化。",
        created_at: iso(daysFromNow: -5, hour: 9)
    )

    static var scheduleDetail: ScheduleDetailRead {
        ScheduleDetailRead(
            schedule: schedules[0],
            position: position,
            round: RoundRead(id: "r1", round_name: "前端终面"),
            resume: resume
        )
    }

    // MARK: 面试进行中（S2，对齐 Figma 633）
    static var roomS2: InterviewPanelPresentation {
        InterviewPanelPresentation(
            connected: true,
            roomPhase: .inRoom,
            phase: .live,
            canEnterRoom: true,
            microphonePermissionGranted: true,
            roomSpeaker: .interviewer,
            participantStatuses: [.lead: .asking, .panelist: .observing, .candidate: .listening],
            liveCaptionText: "先用一分钟介绍你最近主导的产品，重点说说你当时的判断依据。",
            questionSetSynced: true
        )
    }
}

// MARK: - Gallery fakes（仅用于设计审查渲染，不进入真实链路）

private struct GalleryUnavailableError: Error {}

final class GalleryFakeAPI: APIClienting {
    func ensureUser() async throws {}
    func ensureResume() async throws {}
    func createResume(rawText: String) async throws -> ResumeRead { DesignGallerySamples.resume }
    func getCurrentResume() async throws -> ResumeRead { DesignGallerySamples.resume }
    func createSession(positionRoundId: String, companion: Companion) async throws -> SessionRead { throw GalleryUnavailableError() }
    func getSession(id: String) async throws -> SessionRead { throw GalleryUnavailableError() }
    func endSession(id: String) async throws -> SessionRead { throw GalleryUnavailableError() }
    func sessionResults(id: String) async throws -> SessionResultRead { DesignGallerySamples.report }
    func join(sessionId: String) async throws -> JoinResponse { throw GalleryUnavailableError() }
    func parseScheduleDraft(rawInput: String, timezone: String) async throws -> ScheduleDraftRead { throw GalleryUnavailableError() }
    func updateScheduleDraft(id: String, rawInput: String, timezone: String) async throws -> ScheduleDraftRead { throw GalleryUnavailableError() }
    func confirmScheduleDraft(id: String) async throws -> InterviewScheduleRead { DesignGallerySamples.schedules[0] }
    func upcomingSchedules() async throws -> [InterviewScheduleRead] { DesignGallerySamples.schedules }
    func scheduleDetail(id: String) async throws -> ScheduleDetailRead { DesignGallerySamples.scheduleDetail }
    func updateSchedule(id: String, scheduledAt: String?, timezone: String?, durationMinutes: Int?) async throws -> InterviewScheduleRead { DesignGallerySamples.schedules[0] }
    func cancelSchedule(id: String) async throws -> InterviewScheduleRead { DesignGallerySamples.schedules[0] }
    func startSchedule(id: String, companion: Companion) async throws -> ScheduleStartRead { throw GalleryUnavailableError() }
    func agentHome() async throws -> AgentHomeRead { throw GalleryUnavailableError() }
    func updatePositionJD(positionId: String, jdText: String) async throws -> PositionRead { DesignGallerySamples.position }
}

final class GalleryFakeLiveKit: LiveKitControlling {
    var localIdentity: String { "gallery-local" }

    func connect(
        url: String, token: String,
        onSegment: @escaping (String, String, String, Bool) -> Void,
        onParticipantAttributes: @escaping (String, [String: String]) -> Void,
        onCaptionChunk: @escaping (String, String, String) -> Void,
        onState: @escaping (Bool) -> Void,
        onAudioRecoveryFailed: @escaping (String) -> Void
    ) async throws {}

    func connectHomeVoice(
        url: String, token: String,
        onSessionEvent: @escaping (HomeVoiceSessionEvent) -> Void,
        onNavigateInterview: @escaping (Data) -> Void,
        onNavigateHomeAction: @escaping (Data) -> Void,
        onState: @escaping (Bool) -> Void,
        onAudioRecoveryFailed: @escaping (String) -> Void
    ) async throws {}

    func setMicrophone(enabled: Bool) async throws {}
    func disconnect() async {}
}

/// S1 接入中：用空操作 fake 构造的真实房间屏（InterviewSession 默认即 .idle/.connecting）。
private struct GalleryInterviewS1: View {
    @State private var session = InterviewSession(
        config: AppConfig.load(),
        api: GalleryFakeAPI(),
        liveKit: GalleryFakeLiveKit()
    )

    var body: some View {
        InterviewView(session: session, practiceWeakness: { _ in }, returnHome: {})
    }
}

/// S2 进行中：复用真实房间舞台 `RoomStageView`，全屏满铺（与生产同源，无信箱边框）。
private struct GalleryInterviewS2: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.deepSpaceBackground()
            VStack(spacing: 0) {
                RedesignRoomHeader(title: "字节终面", elapsed: "02:14", questionLabel: "Q 2/6", connected: true)
                    .padding(.top, 8)
                RoomStageView(presentation: DesignGallerySamples.roomS2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 用样例数据渲染首页各态（对齐 Figma H1 待机 / H2 聆听→确认）。
private struct GalleryHomeScreen: View {
    let state: QinglanState
    var transcript: String = ""
    var confirmation: ScheduleCreationConfirmation? = nil

    var body: some View {
        VoiceConciergeHomeScreen(
            state: state,
            primaryAction: nil,
            primaryActionPresentation: nil,
            scheduleEntryState: .nextSchedule(label: "明天 14:00 · 字节终面", secondaryLabel: "准备 5 / 6"),
            scheduleUpcomingCount: 1,
            currentTranscript: transcript,
            creationConfirmation: confirmation,
            tapAvatar: {},
            tapPrimaryAction: {},
            tapSchedulePeek: {},
            tapConfirmationViewAll: {},
            tapConfirmationUndo: {},
            dismissCreationConfirmation: {}
        )
    }
}

/// 青岚五态光晕对照（对应样式板 654:133-231）。
struct QinglanStatesGallery: View {
    private let states: [(QinglanState, String, String)] = [
        (.idle, "待机 idle", "光晕缓慢呼吸"),
        (.connecting, "连接 connecting", "虚线光环旋转汇聚"),
        (.listening, "聆听 listening", "双环亮起朝向用户"),
        (.thinking, "思考 thinking", "紫晕 + 思考气泡慢闪"),
        (.speaking, "说话 speaking", "光环随 TTS 音量脉动"),
    ]

    var body: some View {
        ZStack {
            Color.clear.deepSpaceBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Text("青岚 · 五态")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DeepSpaceTheme.primaryText)
                        .padding(.top, 60)
                        .padding(.bottom, 12)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(Array(states.enumerated()), id: \.offset) { _, item in
                            VStack(spacing: 6) {
                                QinglanAvatarView(state: item.0, size: 132)
                                    .frame(width: 170, height: 170)
                                Text(item.1)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DeepSpaceTheme.primaryText)
                                Text(item.2)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(DeepSpaceTheme.tertiaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
    }
}
