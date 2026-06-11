import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ScheduleListModel {
    private(set) var schedules: [InterviewScheduleRead] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: APIClienting

    init(api: APIClienting) {
        self.api = api
    }

    var recentSchedules: [InterviewScheduleRead] {
        sortedSchedules.filter { !ScheduleStatusDisplay(status: $0.status).isEndedBucket }
    }

    var endedSchedules: [InterviewScheduleRead] {
        sortedSchedules.filter { ScheduleStatusDisplay(status: $0.status).isEndedBucket }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            schedules = try await api.upcomingSchedules()
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    private var sortedSchedules: [InterviewScheduleRead] {
        schedules.sorted { lhs, rhs in
            let lhsDate = ScheduleDateFormatter.date(from: lhs.scheduled_at) ?? .distantFuture
            let rhsDate = ScheduleDateFormatter.date(from: rhs.scheduled_at) ?? .distantFuture
            return lhsDate < rhsDate
        }
    }
}

struct ScheduleStatusDisplay: Equatable {
    enum Kind: Equatable {
        case waiting
        case active
        case ended
        case cancelled
    }

    let label: String
    let kind: Kind

    init(status: String) {
        switch status.lowercased() {
        case "in_progress", "started", "live":
            label = "进行中"
            kind = .active
        case "ended", "completed", "done":
            label = "已结束"
            kind = .ended
        case "cancelled", "canceled":
            label = "已取消"
            kind = .cancelled
        default:
            label = "待开始"
            kind = .waiting
        }
    }

    var isEndedBucket: Bool {
        kind == .ended || kind == .cancelled
    }

    var tint: Color {
        switch kind {
        case .waiting:
            return Fig.amber
        case .active:
            return Fig.blue
        case .ended:
            return Fig.success
        case .cancelled:
            return Fig.danger
        }
    }
}

enum ScheduleDateFormatter {
    private static let timezone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        iso8601Fractional.date(from: value) ?? iso8601.date(from: value)
    }

    static func countdownText(for value: String, now: Date = Date()) -> String {
        guard let date = date(from: value) else { return "待定" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0

        if dayDelta <= 0 {
            return "今天 \(clockText(for: date))"
        }
        if dayDelta == 1 {
            return "明天 \(clockText(for: date))"
        }
        return "\(dayDelta) 天"
    }

    static func displayTimeText(for value: String) -> String {
        guard let date = date(from: value) else { return "时间待定" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func clockText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ScheduleListDisplay {
    let schedule: InterviewScheduleRead

    var title: String {
        let company = schedule.company?.trimmedNonEmpty ?? "面试"
        let round = schedule.round_name?.trimmedNonEmpty
            ?? schedule.position_title?.trimmedNonEmpty
            ?? "日程"
        return "\(company) · \(round)"
    }

    var meta: String {
        "\(ScheduleDateFormatter.displayTimeText(for: schedule.scheduled_at)) · 面试 · \(schedule.duration_minutes) 分钟"
    }

    var avatarText: String {
        let source = schedule.company?.trimmedNonEmpty
            ?? schedule.position_title?.trimmedNonEmpty
            ?? "面"
        return String(source.prefix(1))
    }

    var avatarTint: Color {
        switch avatarText {
        case "字":
            return DeepSpaceTheme.amber
        case "蚂":
            return DeepSpaceTheme.reviewGreen
        case "书":
            return DeepSpaceTheme.auroraPurple
        default:
            return DeepSpaceTheme.practiceText
        }
    }

    var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [avatarTint.opacity(0.86), DeepSpaceTheme.auroraCyan.opacity(0.30)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var countdown: String {
        ScheduleDateFormatter.countdownText(for: schedule.scheduled_at)
    }
}

struct ScheduleListView: View {
    @State private var model: ScheduleListModel
    @State private var selectedSchedule: ScheduleSelection?
    @State private var reportSessionID: String?
    @State private var reportResult: SessionResultRead?
    @State private var reportError: String?
    private let api: APIClienting
    let onClose: () -> Void
    let startInterview: (String) -> Void

    init(
        api: APIClienting,
        onClose: @escaping () -> Void = {},
        startInterview: @escaping (String) -> Void = { _ in }
    ) {
        _model = State(initialValue: ScheduleListModel(api: api))
        self.api = api
        self.onClose = onClose
        self.startInterview = startInterview
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topCompanion
                    header
                    content
                }
                .padding(.bottom, 104)
            }

            if let selectedSchedule {
                ScheduleDetailView(
                    scheduleId: selectedSchedule.id,
                    api: api,
                    onBack: { self.selectedSchedule = nil },
                    startInterview: startInterview
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }

            if let reportResult {
                ReportView(
                    result: reportResult,
                    returnHome: {
                        self.reportResult = nil
                        self.reportSessionID = nil
                        onClose()
                    },
                    startAgain: {
                        self.reportResult = nil
                        self.reportSessionID = nil
                        onClose()
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(3)
            } else if reportSessionID != nil {
                ScheduleEmptyState(text: reportError ?? "正在读取报告")
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .zIndex(3)
            }
        }
        .deepSpaceBackground()
        .task {
            await model.refresh()
        }
        .task(id: reportSessionID) {
            await loadReportIfNeeded()
        }
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.height > 36, selectedSchedule == nil {
                        onClose()
                    }
                }
        )
        .animation(.easeOut(duration: 0.22), value: selectedSchedule)
        .animation(.easeOut(duration: 0.22), value: reportResult)
    }

    private func loadReportIfNeeded() async {
        guard let reportSessionID else {
            reportResult = nil
            reportError = nil
            return
        }
        reportError = nil
        do {
            reportResult = try await api.sessionResults(id: reportSessionID)
        } catch let error as APIError {
            reportError = "\(error.errorCode): \(error.userMessage)"
        } catch {
            reportError = "\(error)"
        }
    }

    private var topCompanion: some View {
        VStack(spacing: 12) {
            QinglanAvatarView(state: .idle, size: 58)
                .frame(width: 92, height: 86)
                .opacity(0.75)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.34))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("日程")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
            }

            Spacer()

            Button("收起", action: onClose)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeepSpaceTheme.tertiaryText)
                .buttonStyle(.plain)
                .padding(.top, 4)
        }
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.schedules.isEmpty {
            ScheduleEmptyState(text: "正在读取日程")
                .padding(.top, 42)
        } else if let errorMessage = model.errorMessage, model.schedules.isEmpty {
            ScheduleEmptyState(text: errorMessage)
                .padding(.top, 42)
        } else if model.schedules.isEmpty {
            ScheduleEmptyState(text: "暂无日程")
                .padding(.top, 42)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !model.recentSchedules.isEmpty {
                    ScheduleSectionLabel("近期")
                        .padding(.top, 34)
                    VStack(spacing: 12) {
                        ForEach(model.recentSchedules) { schedule in
                            ScheduleCard(schedule: schedule, isCondensed: false) {
                                selectedSchedule = ScheduleSelection(id: schedule.id)
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                if !model.endedSchedules.isEmpty {
                    ScheduleSectionLabel("已结束")
                        .padding(.top, model.recentSchedules.isEmpty ? 34 : 24)
                    VStack(spacing: 10) {
                        ForEach(model.endedSchedules) { schedule in
                            ScheduleCard(schedule: schedule, isCondensed: true) {
                                if let sessionID = schedule.session_id {
                                    reportSessionID = sessionID
                                } else {
                                    selectedSchedule = ScheduleSelection(id: schedule.id)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

private struct ScheduleSelection: Identifiable, Hashable {
    let id: String
}

private struct ScheduleSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DeepSpaceTheme.tertiaryText)
            .padding(.horizontal, 24)
    }
}

private struct ScheduleCard: View {
    let schedule: InterviewScheduleRead
    let isCondensed: Bool
    let action: () -> Void

    private var display: ScheduleListDisplay {
        ScheduleListDisplay(schedule: schedule)
    }

    private var status: ScheduleStatusDisplay {
        ScheduleStatusDisplay(status: schedule.status)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(display.avatarGradient)
                    .frame(width: isCondensed ? 44 : 52, height: isCondensed ? 44 : 52)
                    .overlay(
                        Text(display.avatarText)
                            .font(.system(size: isCondensed ? 17 : 19, weight: .bold))
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: isCondensed ? 6 : 8) {
                    Text(display.title)
                        .font(.system(size: isCondensed ? 15 : 16, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(display.meta)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !isCondensed {
                        ScheduleStatusInline(status: status)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 14) {
                    if isCondensed {
                        Text("复盘 ›")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DeepSpaceTheme.reviewGreen)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(DeepSpaceTheme.reviewGreen.opacity(0.16))
                            .clipShape(Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(DeepSpaceTheme.reviewGreen.opacity(0.45), lineWidth: 1))
                    } else {
                        let urgent = display.countdown.hasPrefix("今天") || display.countdown.hasPrefix("明天")
                        Text(display.countdown)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(urgent ? DeepSpaceTheme.amber : DeepSpaceTheme.practiceText)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background((urgent ? DeepSpaceTheme.amber : DeepSpaceTheme.practiceText).opacity(0.16))
                            .clipShape(Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }

                    Text("›")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: isCondensed ? 76 : 104, maxHeight: isCondensed ? 76 : 104)
            .glassCard(cornerRadius: 22)
            .opacity(isCondensed ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

private struct ScheduleStatusInline: View {
    let status: ScheduleStatusDisplay

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tint)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.tint)
        }
    }
}

private struct ScheduleEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(DeepSpaceTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 104)
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 20)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
