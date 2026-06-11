import Foundation

struct PreparationItem: Equatable {
    let label: String
    let done: Bool
}

struct SchedulePreparation: Equatable {
    let items: [PreparationItem]

    var completedCount: Int {
        items.filter(\.done).count
    }

    var totalCount: Int {
        items.count
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var summaryText: String {
        guard totalCount > 0 else { return "" }
        return "已就绪 \(completedCount)/\(totalCount)"
    }

    var missingLabels: [String] {
        items.filter { !$0.done }.map(\.label)
    }

    static func derive(detail: ScheduleDetailRead, now: @escaping () -> Date = Date.init) -> SchedulePreparation {
        var items: [PreparationItem] = [
            PreparationItem(label: "简历已上传", done: detail.resume != nil),
            PreparationItem(
                label: "JD 已填",
                done: !detail.position.jd_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
        ]

        if let questionReady = questionReadiness(status: detail.schedule.status, sessionID: detail.schedule.session_id) {
            items.append(PreparationItem(label: "题目已生成", done: questionReady))
        }

        let scheduledDate = ScheduleDateFormatter.date(from: detail.schedule.scheduled_at)
        items.append(PreparationItem(label: "时间已确认", done: scheduledDate.map { $0 > now() } ?? false))

        return SchedulePreparation(items: items)
    }

    private static func questionReadiness(status: String, sessionID: String?) -> Bool? {
        let normalized = status.lowercased()
        if ["ready", "questions_ready", "prepared", "live", "in_progress", "started", "ended", "completed", "done"].contains(normalized) {
            return true
        }
        if ["questions_generating", "generating", "preparing"].contains(normalized) || sessionID != nil {
            return false
        }
        return nil
    }
}
