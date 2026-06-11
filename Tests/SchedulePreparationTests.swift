import XCTest
@testable import InterviewerApp

final class SchedulePreparationTests: XCTestCase {
    func test_derivesPreparationOnlyFromExistingFields() throws {
        let future = try XCTUnwrap(ScheduleDateFormatter.date(from: "2026-06-11T15:00:00+08:00"))
        let detail = ScheduleDetailRead.fixture(
            scheduledAt: "2026-06-12T15:00:00+08:00",
            status: "ready",
            jdText: "岗位 JD",
            resume: ResumeRead(id: "res-1", version: 3, is_current: true, raw_text: "简历", created_at: "2026-06-01T12:00:00+08:00")
        )

        let preparation = SchedulePreparation.derive(detail: detail, now: { future })

        XCTAssertEqual(preparation.items.map(\.label), ["简历已上传", "JD 已填", "题目已生成", "时间已确认"])
        XCTAssertEqual(preparation.items.map(\.done), [true, true, true, true])
        XCTAssertEqual(preparation.completedCount, 4)
        XCTAssertEqual(preparation.totalCount, 4)
        XCTAssertEqual(preparation.summaryText, "已就绪 4/4")
        XCTAssertEqual(preparation.missingLabels, [])
    }

    func test_omitsQuestionItemWhenStatusCannotProveReadiness() throws {
        let now = try XCTUnwrap(ScheduleDateFormatter.date(from: "2026-06-11T15:00:00+08:00"))
        let detail = ScheduleDetailRead.fixture(
            scheduledAt: "2026-06-10T15:00:00+08:00",
            status: "scheduled",
            jdText: "",
            resume: nil
        )

        let preparation = SchedulePreparation.derive(detail: detail, now: { now })

        XCTAssertEqual(preparation.items.map(\.label), ["简历已上传", "JD 已填", "时间已确认"])
        XCTAssertEqual(preparation.items.map(\.done), [false, false, false])
        XCTAssertEqual(preparation.missingLabels, ["简历已上传", "JD 已填", "时间已确认"])
        XCTAssertEqual(preparation.summaryText, "已就绪 0/3")
    }
}

private extension ScheduleDetailRead {
    static func fixture(
        scheduledAt: String,
        status: String,
        jdText: String,
        resume: ResumeRead?
    ) -> ScheduleDetailRead {
        ScheduleDetailRead(
            schedule: InterviewScheduleRead(
                id: "sch-1",
                position_round_id: "pr-1",
                scheduled_at: scheduledAt,
                timezone: "Asia/Shanghai",
                duration_minutes: 45,
                status: status,
                session_id: status == "ready" ? "s-1" : nil,
                raw_command: "字节终面",
                created_at: "2026-06-09T12:00:00Z",
                position_title: "产品经理",
                company: "字节",
                round_name: "终面"
            ),
            position: PositionRead(
                id: "p-1",
                title: "产品经理",
                company: "字节",
                jd_text: jdText,
                seniority: "senior",
                created_at: "2026-06-01T12:00:00Z"
            ),
            round: RoundRead(id: "round-1", round_name: "终面"),
            resume: resume
        )
    }
}
