import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ScheduleDetailModel {
    private(set) var detail: ScheduleDetailRead?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let scheduleId: String
    private let api: APIClienting
    private let now: () -> Date

    init(scheduleId: String, api: APIClienting, now: @escaping () -> Date = Date.init) {
        self.scheduleId = scheduleId
        self.api = api
        self.now = now
    }

    var headerTitle: String {
        guard let schedule = detail?.schedule else { return "面试 · 日程" }
        return ScheduleListDisplay(schedule: schedule).title
    }

    var headerMeta: String {
        guard let detail else { return "" }
        return "\(ScheduleDateFormatter.displayTimeText(for: detail.schedule.scheduled_at)) · \(detail.position.title) · 面试"
    }

    var preparedCount: Int {
        preparation.completedCount
    }

    var preparedTotal: Int { preparation.totalCount }

    var preparationProgress: Double {
        preparation.progress
    }

    var preparation: SchedulePreparation {
        guard let detail else { return SchedulePreparation(items: []) }
        return SchedulePreparation.derive(detail: detail, now: now)
    }

    var countdownTitle: String {
        guard let detail else { return "" }
        let status = ScheduleStatusDisplay(status: detail.schedule.status)
        if status.kind == .active { return "进行中" }
        if status.isEndedBucket { return status.label }
        return ScheduleDateFormatter.countdownText(for: detail.schedule.scheduled_at, now: now())
    }

    var countdownSubtitle: String {
        guard let detail,
              let date = ScheduleDateFormatter.date(from: detail.schedule.scheduled_at)
        else { return "" }
        let seconds = Int(date.timeIntervalSince(now()))
        if seconds <= 0 { return "已到开始时间" }
        let hours = max(1, seconds / 3600)
        return "距开始 \(hours) 小时"
    }

    var resumeReadiness: ResumeReadinessDisplay {
        guard let resume = detail?.resume else {
            return ResumeReadinessDisplay(label: "未上传 · 去补充", kind: .missing)
        }
        guard let created = ScheduleDateFormatter.date(from: resume.created_at) else {
            return ResumeReadinessDisplay(label: "v\(resume.version) · 建议更新", kind: .suggestUpdate)
        }
        let age = Calendar(identifier: .gregorian).dateComponents([.day], from: created, to: now()).day ?? 0
        if age > 30 {
            return ResumeReadinessDisplay(label: "v\(resume.version) · 建议更新", kind: .suggestUpdate)
        }
        return ResumeReadinessDisplay(label: "v\(resume.version) · 已就绪", kind: .ready)
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await api.scheduleDetail(id: scheduleId)
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    func cancel() async {
        guard let detail else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let schedule = try await api.cancelSchedule(id: detail.schedule.id)
            self.detail = ScheduleDetailRead(
                schedule: schedule,
                position: detail.position,
                round: detail.round,
                resume: detail.resume
            )
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    func rescheduleOneDayLater() async {
        guard let detail,
              let current = ScheduleDateFormatter.date(from: detail.schedule.scheduled_at)
        else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: detail.schedule.timezone) ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: current) else { return }
        let nextValue = ScheduleDetailModel.isoString(nextDate, timezone: calendar.timeZone)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let schedule = try await api.updateSchedule(
                id: detail.schedule.id,
                scheduledAt: nextValue,
                timezone: detail.schedule.timezone,
                durationMinutes: detail.schedule.duration_minutes
            )
            self.detail = ScheduleDetailRead(
                schedule: schedule,
                position: detail.position,
                round: detail.round,
                resume: detail.resume
            )
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    private static func isoString(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }
}

struct ResumeReadinessDisplay: Equatable {
    enum Kind: Equatable {
        case ready
        case suggestUpdate
        case missing
    }

    let label: String
    let kind: Kind

    var tint: Color {
        switch kind {
        case .ready:
            return Fig.success
        case .suggestUpdate, .missing:
            return Fig.amber
        }
    }
}

struct ScheduleDetailView: View {
    @State private var model: ScheduleDetailModel
    @State private var editContext: ScheduleEditContext?
    private let api: APIClienting
    let onBack: () -> Void
    let startInterview: (String) -> Void

    init(
        scheduleId: String,
        api: APIClienting,
        onBack: @escaping () -> Void = {},
        startInterview: @escaping (String) -> Void = { _ in }
    ) {
        _model = State(initialValue: ScheduleDetailModel(scheduleId: scheduleId, api: api))
        self.api = api
        self.onBack = onBack
        self.startInterview = startInterview
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Button("‹ 日程", action: onBack)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.secondaryText)
                        .buttonStyle(.plain)
                        .padding(.top, 56)
                        .padding(.horizontal, 24)

                    if let detail = model.detail {
                        headerCard(detail)
                        jdCard(detail)
                        resumeCard(detail)
                        actionArea(detail)
                    } else {
                        ScheduleDetailPlaceholder(text: model.errorMessage ?? "正在读取日程")
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 34)
            }

            if let editContext {
                ScheduleEditSheetView(
                    kind: editContext.kind,
                    detail: editContext.detail,
                    api: api,
                    dismiss: { self.editContext = nil },
                    saved: {
                        await model.refresh()
                        self.editContext = nil
                    }
                )
            }
        }
        .deepSpaceBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.refresh()
        }
    }

    private func headerCard(_ detail: ScheduleDetailRead) -> some View {
        let display = ScheduleListDisplay(schedule: detail.schedule)
        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 13) {
                Circle()
                    .fill(display.avatarGradient)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(display.avatarText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text(model.headerTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(model.headerMeta)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.countdownTitle)
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                if !model.countdownSubtitle.isEmpty {
                    Text(model.countdownSubtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.amber)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.preparation.summaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.tertiaryText)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.16))
                        Capsule(style: .continuous)
                            .fill(DeepSpaceTheme.auroraCyan)
                            .frame(width: proxy.size.width * model.preparationProgress)
                    }
                }
                .frame(height: 6)

                if !model.preparation.missingLabels.isEmpty {
                    Text(model.preparation.missingLabels.joined(separator: " · "))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func jdCard(_ detail: ScheduleDetailRead) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DeepSpaceTheme.auroraCyan)
                    .frame(width: 7, height: 7)
                Text("岗位要求 · JD")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                Spacer()
                Button("编辑") {
                    editContext = ScheduleEditContext(kind: .jd, detail: detail)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeepSpaceTheme.auroraCyan)
                .buttonStyle(.plain)
            }

            Text(detail.position.jd_text.isEmpty ? "未填写" : detail.position.jd_text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DeepSpaceTheme.secondaryText)
                .lineSpacing(4)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .glassCard(cornerRadius: 22)
        .padding(.horizontal, 20)
    }

    private func resumeCard(_ detail: ScheduleDetailRead) -> some View {
        Button {
            editContext = ScheduleEditContext(kind: .resume, detail: detail)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(displayAvatarGradient(for: detail))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text("简")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("本场简历")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.primaryText)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(resumeTint)
                            .frame(width: 6, height: 6)
                        Text(model.resumeReadiness.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(resumeTint)
                    }
                }

                Spacer()

                Text("编辑 ›")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80)
            .glassCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func actionArea(_ detail: ScheduleDetailRead) -> some View {
        VStack(spacing: 14) {
            Button {
                startInterview(detail.schedule.id)
            } label: {
                Text("开始面试")
            }
            .buttonStyle(PrimaryCTAStyle())

            HStack(spacing: 18) {
                Button {
                    Task { await model.rescheduleOneDayLater() }
                } label: {
                    Text("改期")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.secondaryText)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 14)

                Button {
                    Task { await model.cancel() }
                } label: {
                    Text("取消面试")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.dangerText)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DeepSpaceTheme.dangerText)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var resumeTint: Color {
        switch model.resumeReadiness.kind {
        case .ready:
            return DeepSpaceTheme.reviewGreen
        case .suggestUpdate, .missing:
            return DeepSpaceTheme.amber
        }
    }

    private func displayAvatarGradient(for detail: ScheduleDetailRead) -> LinearGradient {
        LinearGradient(
            colors: [DeepSpaceTheme.auroraPurple.opacity(0.80), DeepSpaceTheme.auroraCyan.opacity(0.30)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ScheduleEditContext {
    let kind: ScheduleEditKind
    let detail: ScheduleDetailRead
}

struct ScheduleDetailPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(DeepSpaceTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 160)
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 20)
    }
}
