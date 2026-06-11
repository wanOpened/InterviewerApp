import Foundation
import Observation

enum HomeSchedulePeekEntryState: Equatable {
    case nextSchedule(label: String, secondaryLabel: String?)
    case empty
}

@MainActor
@Observable
final class HomeSchedulePeekModel {
    private(set) var schedules: [InterviewScheduleRead] = []
    private(set) var errorMessage: String?
    private(set) var creationConfirmation: ScheduleCreationConfirmation?
    private(set) var nextPreparation: SchedulePreparation?

    private let api: APIClienting
    private var creationSnapshotIDs: Set<String>?

    init(api: APIClienting) {
        self.api = api
    }

    var upcomingCount: Int {
        schedules.count
    }

    var isVisible: Bool {
        true
    }

    var entryState: HomeSchedulePeekEntryState {
        guard let schedule = nextSchedule else {
            return .empty
        }
        let display = ScheduleListDisplay(schedule: schedule)
        let label = "\(display.countdown) · \(display.title.replacingOccurrences(of: " · ", with: ""))"
        return .nextSchedule(label: label, secondaryLabel: nextPreparation?.summaryText.trimmedNonEmpty)
    }

    var label: String {
        switch entryState {
        case .nextSchedule(let label, _):
            return label
        case .empty:
            return "暂无安排"
        }
    }

    var secondaryLabel: String? {
        switch entryState {
        case .nextSchedule(_, let secondaryLabel):
            return secondaryLabel
        case .empty:
            return nil
        }
    }

    var nextSchedule: InterviewScheduleRead? {
        schedules.sorted { lhs, rhs in
            let lhsDate = ScheduleDateFormatter.date(from: lhs.scheduled_at) ?? .distantFuture
            let rhsDate = ScheduleDateFormatter.date(from: rhs.scheduled_at) ?? .distantFuture
            return lhsDate < rhsDate
        }
        .first
    }

    func refresh() async {
        errorMessage = nil
        do {
            schedules = try await loadUpcomingSchedules()
            await refreshNextPreparation()
        } catch let e as APIError {
            schedules = []
            nextPreparation = nil
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            schedules = []
            nextPreparation = nil
            errorMessage = "\(error)"
        }
    }

    func captureCreationSnapshot() {
        creationSnapshotIDs = Set(schedules.map(\.id))
    }

    func refreshAfterVoiceActivity() async {
        guard let snapshotIDs = creationSnapshotIDs else { return }
        creationSnapshotIDs = nil
        do {
            let latestSchedules = try await loadUpcomingSchedules()
            schedules = latestSchedules
            await refreshNextPreparation()
            creationConfirmation = latestSchedules
                .filter { !snapshotIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    let lhsDate = ScheduleDateFormatter.date(from: lhs.scheduled_at) ?? .distantFuture
                    let rhsDate = ScheduleDateFormatter.date(from: rhs.scheduled_at) ?? .distantFuture
                    return lhsDate < rhsDate
                }
                .first
                .map(ScheduleCreationConfirmation.init(schedule:))
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    func dismissCreationConfirmation() {
        creationConfirmation = nil
    }

    func cancelCreationConfirmation() async {
        guard let confirmation = creationConfirmation else { return }
        creationConfirmation = nil
        do {
            _ = try await api.cancelSchedule(id: confirmation.scheduleID)
            schedules = try await loadUpcomingSchedules()
            await refreshNextPreparation()
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func loadUpcomingSchedules() async throws -> [InterviewScheduleRead] {
        try await api.upcomingSchedules()
    }

    private func refreshNextPreparation() async {
        guard let schedule = nextSchedule else {
            nextPreparation = nil
            return
        }
        do {
            let detail = try await api.scheduleDetail(id: schedule.id)
            nextPreparation = SchedulePreparation.derive(detail: detail)
        } catch {
            nextPreparation = nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct ScheduleCreationConfirmation: Equatable {
    let scheduleID: String
    let summary: String

    init(scheduleID: String, summary: String) {
        self.scheduleID = scheduleID
        self.summary = summary
    }

    init(schedule: InterviewScheduleRead) {
        scheduleID = schedule.id
        summary = Self.summary(for: schedule)
    }

    private static func summary(for schedule: InterviewScheduleRead) -> String {
        [
            timeLabel(for: schedule),
            schedule.company,
            schedule.round_name,
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
    }

    private static func timeLabel(for schedule: InterviewScheduleRead) -> String? {
        guard let date = ScheduleDateFormatter.date(from: schedule.scheduled_at) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timezone) ?? .current
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdays[max(0, min(weekdayIndex, weekdays.count - 1))]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(weekday) \(formatter.string(from: date))"
    }
}
