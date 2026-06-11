import XCTest
@testable import InterviewerApp

final class ReportViewModelTests: XCTestCase {
    func test_mapsSessionResultIntoReportSections() throws {
        let data = """
        {
          "session_id": "s-1",
          "overall_score": 78,
          "dimension_scores": {},
          "dimensions": [
            {"key": "structure", "label": "结构化表达", "score": 82, "is_weakest": false},
            {"key": "business", "label": "业务洞察", "score": 74, "is_weakest": false},
            {"key": "data", "label": "数据思维", "score": 71, "is_weakest": true},
            {"key": "empathy", "label": "用户同理心", "score": 80, "is_weakest": false},
            {"key": "reaction", "label": "临场反应", "score": 76, "is_weakest": false}
          ],
          "weakest_dimension": "data",
          "practice_round_id": "pr-1",
          "tip": "先补数据假设。",
          "per_question_review": [
            {
              "question": "如何定义问题？",
              "score": 13,
              "answer": "先归因。",
              "better_answer": "补充数据假设。",
              "strengths": ["结构清晰"]
            },
            {
              "question_text": "如何评估功能？",
              "score": 16,
              "candidate_answer": "看留存。",
              "improved_answer": "区分短期和长期指标。"
            }
          ],
          "coaching_plan": {
            "items": [
              {"title": "数据思维 · 漏斗拆解专项", "subtitle": "针对 Q1 的分层定位短板", "duration": "15 分钟"},
              {"title": "STAR 结构表达训练", "subtitle": "回答收尾信号", "duration_minutes": 10}
            ]
          },
          "is_partial": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SessionResultRead.self, from: data)
        let viewModel = ReportViewModel(
            result: result,
            context: ReportContext(company: "字节", round: "终面", dateText: "6月9日", durationText: "28 分钟")
        )

        XCTAssertEqual(viewModel.overallScore, 78)
        XCTAssertEqual(viewModel.title, "字节终面 · 复盘报告")
        XCTAssertEqual(viewModel.dimensions.map(\.label), ["结构化表达", "业务洞察", "数据思维", "用户同理心", "临场反应"])
        XCTAssertEqual(viewModel.dimensions.filter(\.isWeakest).map(\.key), ["data"])
        XCTAssertEqual(viewModel.reviewCards.count, 2)
        XCTAssertEqual(viewModel.reviewCards[0].question, "如何定义问题？")
        XCTAssertEqual(viewModel.reviewCards[0].answer, "先归因。")
        XCTAssertEqual(viewModel.reviewCards[0].betterAnswer, "补充数据假设。")
        XCTAssertEqual(viewModel.practiceItems.map(\.title), ["数据思维 · 漏斗拆解专项", "STAR 结构表达训练"])
        XCTAssertEqual(viewModel.practiceItems.map(\.durationText), ["15 分钟", "10 分钟"])
    }

    func test_doesNotInventMissingReviewOrPracticeCopy() {
        let result = SessionResultRead(
            session_id: "s-empty",
            overall_score: 80,
            dimension_scores: ["metric": .int(80)],
            per_question_review: [[:]],
            coaching_plan: [:],
            is_partial: false
        )

        let viewModel = ReportViewModel(result: result, context: .empty)

        XCTAssertEqual(viewModel.reviewCards, [])
        XCTAssertEqual(viewModel.practiceItems, [])
    }
}
