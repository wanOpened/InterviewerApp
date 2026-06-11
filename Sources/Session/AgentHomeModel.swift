import Foundation
import Observation

struct BriefingItem: Equatable {
    let sourceTag: SourceTag.Kind
    let title: String
    let reason: String
    let cta: String
    let actionType: String
    let target: [String: String]
    let emphasized: Bool
}

@MainActor
@Observable
final class AgentHomeModel {
    private(set) var recommendation: AgentHomeRead?
    private(set) var qinglanState: QinglanState = .idle
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var voiceTranscript = ""

    private let api: APIClienting

    init(api: APIClienting) {
        self.api = api
    }

    var primaryTitle: String {
        recommendation?.primary_action.title ?? "青岚正在判断下一步"
    }

    var primaryReason: String {
        recommendation?.primary_action.reason ?? "我会根据你的面试日程、JD、练习和复盘判断最重要的一步。"
    }

    var primaryCTA: String {
        recommendation?.primary_action.cta ?? "让青岚判断"
    }

    var primaryActionType: String? {
        recommendation?.primary_action.type
    }

    var spokenPrompt: String {
        recommendation?.primary_action.spoken_prompt ?? "我先看一下你现在最该做什么。"
    }

    var briefingNarration: String {
        guard let recommendation else { return spokenPrompt }
        let action = recommendation.primary_action
        return [action.spoken_prompt, action.title, action.reason]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix("。") ? $0 : "\($0)。" }
            .joined()
    }

    var target: [String: String] {
        recommendation?.primary_action.target ?? [:]
    }

    var signalLabels: [String] {
        recommendation?.signals.map(\.label) ?? ["读取中"]
    }

    var briefingItems: [BriefingItem] {
        guard let recommendation else { return [] }
        if let items = recommendation.briefing_items {
            return items.map { item in
                BriefingItem(
                    sourceTag: Self.sourceTag(forBriefingSource: item.source),
                    title: item.title,
                    reason: item.reason,
                    cta: item.cta,
                    actionType: item.action_type,
                    target: item.target,
                    emphasized: item.emphasis
                )
            }
        }

        let action = recommendation.primary_action
        let primary = BriefingItem(
            sourceTag: Self.sourceTag(forActionType: action.type),
            title: action.title,
            reason: action.reason,
            cta: action.cta,
            actionType: action.type,
            target: action.target,
            emphasized: true
        )
        let signals = recommendation.signals.map { signal in
            BriefingItem(
                sourceTag: Self.sourceTag(forSignalType: signal.type),
                title: signal.label,
                reason: Self.reason(for: signal),
                cta: Self.cta(forSignalType: signal.type),
                actionType: action.type,
                target: action.target,
                emphasized: false
            )
        }
        return [primary] + signals
    }

    var lightweightItems: [BriefingItem] {
        var items = Array(briefingItems.dropFirst().prefix(2))
        if !items.contains(where: { $0.actionType == AgentHomeActionType.quickStart.rawValue }) {
            items.append(quickPracticeFallback)
        }
        return items
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        qinglanState = .thinking
        defer { isLoading = false }

        do {
            try await api.ensureUser()
            recommendation = try await api.agentHome()
            qinglanState = .speaking
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
            qinglanState = .error
        } catch {
            errorMessage = "\(error)"
            qinglanState = .error
        }
    }

    func beginListening() {
        errorMessage = nil
        voiceTranscript = ""
        if qinglanState != .thinking {
            qinglanState = .listening
        }
    }

    func applyRecognizerTranscript(_ text: String) {
        voiceTranscript = text
        if qinglanState != .thinking {
            qinglanState = .listening
        }
    }

    func finishListening() {
        if qinglanState == .listening {
            qinglanState = .idle
        }
    }

    func beginSpeaking() {
        errorMessage = nil
        qinglanState = .speaking
    }

    func finishSpeaking() {
        if qinglanState == .speaking {
            qinglanState = .waiting
        }
    }

    func showLocalError(_ message: String) {
        errorMessage = message
        qinglanState = .error
    }

    func updateJD(_ jdText: String) async {
        guard let positionId = target["position_id"] else {
            showLocalError("青岚还不知道这份 JD 对应哪个岗位。")
            return
        }
        let cleaned = jdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            showLocalError("JD 不能为空")
            return
        }

        isLoading = true
        errorMessage = nil
        qinglanState = .thinking
        defer { isLoading = false }

        do {
            _ = try await api.updatePositionJD(positionId: positionId, jdText: cleaned)
            recommendation = try await api.agentHome()
            qinglanState = .speaking
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
            qinglanState = .error
        } catch {
            errorMessage = "\(error)"
            qinglanState = .error
        }
    }

    private static func sourceTag(forBriefingSource source: String) -> SourceTag.Kind {
        switch source {
        case "interview": return .interview
        case "review": return .review
        case "schedule": return .schedule
        case "practice": return .practice
        default: return .practice
        }
    }

    private static func sourceTag(forActionType type: String) -> SourceTag.Kind {
        switch type {
        case "start_practice", "practice_weakness", "resume_live_session", "quick_start":
            return .interview
        case "review_result", "wait_scoring":
            return .review
        case "create_schedule", "create_target", "add_jd":
            return .schedule
        default:
            return .practice
        }
    }

    private static func sourceTag(forSignalType type: String) -> SourceTag.Kind {
        let normalized = type.lowercased()
        if normalized.contains("result") || normalized.contains("review") || normalized.contains("scoring") {
            return .review
        }
        if normalized.contains("schedule") || normalized.contains("upcoming") || normalized.contains("interview") {
            return .schedule
        }
        if normalized.contains("practice") || normalized.contains("weak") {
            return .practice
        }
        return .interview
    }

    private static func reason(for signal: AgentHomeSignal) -> String {
        signal.severity.lowercased() == "high" ? "青岚建议优先关注" : "值得提前准备"
    }

    private static func cta(forSignalType type: String) -> String {
        switch sourceTag(forSignalType: type) {
        case .review: return "查看"
        case .schedule: return "准备"
        case .interview, .practice: return "去练"
        }
    }

    private var quickPracticeFallback: BriefingItem {
        BriefingItem(
            sourceTag: .interview,
            title: "快练 10 分钟",
            reason: "没有目标也能先体验一轮",
            cta: "开始",
            actionType: AgentHomeActionType.quickStart.rawValue,
            target: recommendation?.primary_action.target ?? [:],
            emphasized: false
        )
    }
}
