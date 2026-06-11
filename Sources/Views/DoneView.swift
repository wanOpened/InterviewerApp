import SwiftUI

struct DoneView: View {
    let sessionId: String?
    let companion: Companion
    let loadResult: () async throws -> SessionResultRead
    let practiceWeakness: (BriefingItem) -> Void
    let returnHome: () -> Void
    var reportContext: ReportContext = .empty

    @State private var state: ResultState = .loading
    @State private var isShowingReport = false

    var body: some View {
        content
        .task(id: sessionId) {
            await pollResult()
        }
        .fullScreenCover(isPresented: $isShowingReport) {
            if case .ready(let result) = state {
                ReportView(result: result, context: reportContext, returnHome: returnHome, startAgain: returnHome)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            DoneStageScreen(
                statusText: "评分生成中",
                statusColor: DeepSpaceTheme.auroraCyan,
                primaryTitle: nil,
                primaryAction: {},
                returnHome: returnHome
            )
        case .failed(let message):
            DoneStageScreen(
                statusText: message.isEmpty ? "本场未能完成评分" : "本场未能完成评分",
                statusColor: DeepSpaceTheme.practiceText,
                primaryTitle: nil,
                primaryAction: {},
                returnHome: returnHome
            )
        case .ready(let result):
            DoneStageScreen(
                statusText: "已出分",
                statusColor: DeepSpaceTheme.auroraCyan,
                primaryTitle: "查看报告 ›",
                primaryAction: { isShowingReport = true },
                returnHome: returnHome
            )
        }
    }

    private func pollResult() async {
        state = .loading
        for attempt in 0..<24 {
            do {
                state = .ready(try await loadResult())
                return
            } catch let error as APIError {
                if error.errorCode == "SESSION_NOT_READY" {
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds(attempt: attempt))
                    continue
                }
                state = .failed("")
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                state = .failed("")
                return
            }
        }
        state = .failed("")
    }

    private func retryDelayNanoseconds(attempt: Int) -> UInt64 {
        let seconds = min(12, max(2, 1 << min(attempt, 4)))
        return UInt64(seconds) * 1_000_000_000
    }
}

private struct DoneStageScreen: View {
    let statusText: String
    let statusColor: Color
    let primaryTitle: String?
    let primaryAction: () -> Void
    let returnHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 180)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(DeepSpaceTheme.auroraCyan.opacity(0.20 - Double(index) * 0.05), lineWidth: 1)
                        .frame(width: 154 + CGFloat(index * 44), height: 154 + CGFloat(index * 44))
                }
                QinglanAvatarView(state: .idle, size: 136)
                    .frame(width: 210, height: 210)
            }
            .frame(height: 252)

            Text("本场面试已结束")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(DeepSpaceTheme.primaryText)
                .padding(.top, 24)

            AccentChip(text: statusText, color: statusColor)
                .padding(.top, 22)

            Spacer(minLength: 0)

            if let primaryTitle {
                Button(primaryTitle, action: primaryAction)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .glassCard(cornerRadius: 27)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }

            Button("回到首页", action: returnHome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DeepSpaceTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .glassCard(cornerRadius: 27)
                .padding(.horizontal, 20)
                .padding(.bottom, 66)
        }
        .deepSpaceBackground()
    }
}

struct ResultDimension: Equatable {
    let key: String
    let label: String
    let score: Int
    let isWeak: Bool
}

struct ResultPresentation {
    private static let dimensionSpecs: [(key: String, label: String)] = [
        ("user_insight", "用户洞察"),
        ("need_dig", "需求挖掘"),
        ("solution", "方案设计"),
        ("tradeoff", "取舍判断"),
        ("metric", "衡量指标"),
    ]

    let overallScore: Int
    let dimensions: [ResultDimension]
    let weakDimension: ResultDimension
    let tip: String
    let contextLabel: String
    let practiceGoal: String
    let practiceItem: BriefingItem

    init(result: SessionResultRead) {
        overallScore = result.overall_score
        let typedDimensions = result.dimensions ?? []
        let resolvedDimensions: [ResultDimension]
        if typedDimensions.isEmpty {
            let scores = Self.dimensionSpecs.map { spec in
                (spec.key, spec.label, Self.score(for: spec.key, in: result.dimension_scores))
            }
            let weakKey = result.weakest_dimension
                ?? scores.min { $0.2 < $1.2 }?.0
                ?? Self.dimensionSpecs[0].key
            resolvedDimensions = scores.map {
                ResultDimension(key: $0.0, label: $0.1, score: $0.2, isWeak: $0.0 == weakKey)
            }
        } else {
            resolvedDimensions = typedDimensions.map {
                ResultDimension(
                    key: $0.key,
                    label: $0.label,
                    score: Self.normalizedScore($0.score),
                    isWeak: $0.is_weakest
                )
            }
        }
        dimensions = resolvedDimensions
        weakDimension = resolvedDimensions.first(where: \.isWeak)
            ?? resolvedDimensions.min { $0.score < $1.score }
            ?? ResultDimension(key: "unknown", label: "待复盘", score: 0, isWeak: true)
        tip = result.immediateFocus
        contextLabel = result.coaching_plan["context_label"]?.stringValue
            ?? result.coaching_plan["interview_context"]?.stringValue
            ?? "面试复盘"
        practiceGoal = result.coaching_plan["practice_goal"]?.stringValue
            ?? result.nextSessionSuggestion

        let weakKey = result.weakest_dimension
            ?? dimensions.first(where: \.isWeak)?.key
            ?? dimensions.min(by: { $0.score < $1.score })?.key
            ?? Self.dimensionSpecs[0].key
        var target = [
            "session_id": result.session_id,
            "weak_dimension": weakKey,
        ]
        if let positionRoundId = result.practice_round_id
            ?? result.coaching_plan["position_round_id"]?.stringValue {
            target["position_round_id"] = positionRoundId
        }
        let weakLabel = dimensions.first(where: \.isWeak)?.label ?? "弱项"
        practiceItem = BriefingItem(
            sourceTag: .practice,
            title: "针对「\(weakLabel)」再练一次",
            reason: result.nextSessionSuggestion,
            cta: "再练弱项",
            actionType: "practice_weakness",
            target: target,
            emphasized: true
        )
    }

    private static func score(for key: String, in values: [String: JSONValue]) -> Int {
        guard let value = values[key] else { return 0 }
        let raw: Int?
        if case .object(let object) = value {
            raw = object["score"]?.intValue
        } else {
            raw = value.intValue
        }
        guard let raw else { return 0 }
        return normalizedScore(raw)
    }

    private static func normalizedScore(_ raw: Int) -> Int {
        max(0, min(raw <= 10 ? raw * 10 : raw, 100))
    }
}

private enum ResultState: Equatable {
    case loading
    case ready(SessionResultRead)
    case failed(String)
}

private struct ResultWaitingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .tint(Color(hex: 0x2387FF))
            Text("正在生成复盘")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x121926))
            Text("我会把这轮回答拆成维度分、问题反馈和下一步训练。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6C7786))
                .fixedSize(horizontal: false, vertical: true)
        }
        .resultCard()
    }
}

private struct ResultErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("复盘暂时不可用")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x121926))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xA04444))
                .fixedSize(horizontal: false, vertical: true)
            Button("重试", action: retry)
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.borderedProminent)
        }
        .resultCard()
    }
}

private struct ResultReadyCard: View {
    let presentation: ResultPresentation
    let companion: Companion
    let practiceWeakness: (BriefingItem) -> Void
    let returnHome: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("9:41")
                .resultFont(13, weight: .semibold, color: Fig.ink)
                .resultFrame(x: 27, y: 16, width: 60, height: 16, alignment: .leading)

            Button(action: returnHome) {
                Text("完成")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Fig.blue)
                    .frame(width: 64, height: 34)
                    .background(.white)
                    .clipShape(Capsule(style: .continuous))
                    .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.30).opacity(0.06), radius: 6, y: 6)
            }
            .buttonStyle(.plain)
            .resultFrame(x: 20, y: 52, width: 64, height: 34)

            Text(presentation.contextLabel)
                .resultFont(13, weight: .medium, color: Fig.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .resultFrame(x: 236, y: 62, width: 134, height: 18, alignment: .trailing)

            Text("复盘完成")
                .resultFont(36, weight: .bold, color: Fig.ink)
                .multilineTextAlignment(.center)
                .resultFrame(x: 34, y: 118, width: 322, height: 44)

            Text("\(companion.displayName)已整理出下一步重点")
                .resultFont(15, weight: .semibold, color: Fig.blue)
                .multilineTextAlignment(.center)
                .resultFrame(x: 34, y: 174, width: 322, height: 22)

            Text("下一步，补「\(presentation.weakDimension.label)」")
                .resultFont(26, weight: .bold, color: Fig.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 34, y: 278, width: 322, height: 58)

            Text(resultSummary)
                .resultFont(15, weight: .regular, color: Fig.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 36, y: 346, width: 322, height: 44)

            ResultReadinessCard(presentation: presentation)
                .resultFrame(x: 20, y: 384, width: 350, height: 112)

            ResultCoachCard(presentation: presentation)
                .resultFrame(x: 20, y: 514, width: 350, height: 170)

            ResultAbilityOverviewCompact(dimensions: presentation.dimensions)
                .resultFrame(x: 20, y: 704, width: 350, height: 58)

            ZStack(alignment: .topLeading) {
                Color(hex: 0xF7FBFF, opacity: 0.96)
                Button {
                    practiceWeakness(presentation.practiceItem)
                } label: {
                    Text("再练一次\(presentation.weakDimension.label)追问")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 350, height: 52)
                        .background(Fig.blue)
                        .clipShape(Capsule(style: .continuous))
                        .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.30).opacity(0.10), radius: 9, y: 8)
                }
                .buttonStyle(.plain)
                .resultFrame(x: 20, y: 14, width: 350, height: 52)
            }
            .resultFrame(x: 0, y: 772, width: 390, height: 88)
        }
    }

    private var resultSummary: String {
        if !presentation.tip.isEmpty { return presentation.tip }
        if !presentation.practiceItem.reason.isEmpty { return presentation.practiceItem.reason }
        return ""
    }
}

private struct ResultReadinessCard: View {
    let presentation: ResultPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Fig.blue)
                .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.30).opacity(0.12), radius: 15, y: 14)
            Text("\(presentation.overallScore)")
                .resultFont(54, weight: .bold, color: .white)
                .resultFrame(x: 24, y: 20, width: 92, height: 58, alignment: .leading)
            Text("/100")
                .resultFont(17, weight: .medium, color: Color(hex: 0xDBEDFF))
                .resultFrame(x: 110, y: 48, width: 70, height: 22, alignment: .leading)
            Text("面试准备度")
                .resultFont(14, weight: .medium, color: Color(hex: 0xE0F2FF))
                .resultFrame(x: 24, y: 78, width: 120, height: 20, alignment: .leading)
            Text(presentation.practiceItem.reason)
                .resultFont(14, weight: .regular, color: Color(hex: 0xEDF7FF))
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 154, y: 32, width: 178, height: 58, alignment: .leading)
        }
    }
}

private struct ResultCoachCard: View {
    let presentation: ResultPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.30).opacity(0.07), radius: 12, y: 10)
            Text("最该补")
                .resultFont(12, weight: .medium, color: Fig.danger)
                .frame(width: 58, height: 24)
                .background(Color(hex: 0xFFEDF2))
                .clipShape(Capsule(style: .continuous))
                .resultFrame(x: 18, y: 18, width: 58, height: 24)
            Text(presentation.weakDimension.label)
                .resultFont(18, weight: .bold, color: Fig.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 86, y: 17, width: 170, height: 26, alignment: .leading)
            Text("\(presentation.weakDimension.score)")
                .resultFont(18, weight: .bold, color: Fig.danger)
                .resultFrame(x: 288, y: 18, width: 32, height: 24, alignment: .trailing)
            Text(presentation.tip)
                .resultFont(14, weight: .regular, color: Fig.muted)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 18, y: 56, width: 314, height: 58, alignment: .leading)
            Rectangle()
                .fill(Fig.line)
                .resultFrame(x: 18, y: 118, width: 314, height: 1)
            Text(practiceGoalText)
                .resultFont(14, weight: .medium, color: Fig.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .resultFrame(x: 18, y: 132, width: 314, height: 38, alignment: .leading)
        }
    }

    private var practiceGoalText: String {
        guard !presentation.practiceGoal.isEmpty else { return "" }
        return "练习目标：\(presentation.practiceGoal)"
    }
}

private struct ResultAbilityOverviewCompact: View {
    let dimensions: [ResultDimension]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.30).opacity(0.05), radius: 10, y: 8)
            Text("能力概览")
                .resultFont(15, weight: .semibold, color: Fig.ink)
                .resultFrame(x: 18, y: 14, width: 76, height: 20, alignment: .leading)

            ForEach(Array(displayDimensions.enumerated()), id: \.offset) { index, dimension in
                MiniDimensionBar(dimension: dimension)
                    .resultFrame(x: 104 + CGFloat(index * 43), y: 20, width: 34, height: 36)
            }
        }
    }

    private var displayDimensions: [ResultDimension] {
        Array(dimensions.prefix(5))
    }
}

private struct MiniDimensionBar: View {
    let dimension: ResultDimension

    private var tint: Color {
        if dimension.isWeak || dimension.score < 60 { return Fig.danger }
        if dimension.score < 75 { return Fig.amber }
        return Fig.success
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(Fig.line)
                .resultFrame(x: 0, y: 0, width: 28, height: 5)
            Capsule(style: .continuous)
                .fill(tint)
                .resultFrame(x: 0, y: 0, width: 28 * CGFloat(max(0, min(dimension.score, 100))) / 100, height: 5)
            Text(shortLabel)
                .resultFont(10, weight: .medium, color: dimension.isWeak ? Fig.danger : Fig.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .resultFrame(x: -3, y: 11, width: 34, height: 14)
        }
    }

    private var shortLabel: String {
        switch dimension.key {
        case "user_insight": return "洞察"
        case "need_dig": return "需求"
        case "solution": return "方案"
        case "tradeoff": return "取舍"
        case "metric": return "指标"
        default: return String(dimension.label.suffix(2))
        }
    }
}

private struct ResultSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x6C7786))
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x121926))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func resultFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, alignment: Alignment = .center) -> some View {
        frame(width: width, height: height, alignment: alignment)
            .position(x: x + width / 2, y: y + height / 2)
    }

    func resultFont(_ size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .tracking(0)
    }

    func resultCard() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: 0xE5ECF2), lineWidth: 1)
            )
    }
}

private struct ResultDeviceCanvas<Content: View>: View {
    var background: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
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
            .background(background.ignoresSafeArea())
        }
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
