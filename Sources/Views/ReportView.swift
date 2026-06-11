import SwiftUI

struct ReportContext: Equatable {
    let company: String?
    let round: String?
    let dateText: String?
    let durationText: String?

    static let empty = ReportContext(company: nil, round: nil, dateText: nil, durationText: nil)
}

struct ReportDimension: Equatable {
    let key: String
    let label: String
    let score: Int
    let isWeakest: Bool
}

struct ReportReviewCard: Equatable {
    let index: Int
    let question: String
    let scoreText: String?
    let answer: String?
    let betterAnswer: String?
}

struct ReportPracticeItem: Equatable {
    let title: String
    let subtitle: String?
    let durationText: String?
}

struct ReportViewModel: Equatable {
    let sessionID: String
    let overallScore: Int
    let title: String
    let metaText: String
    let dimensions: [ReportDimension]
    let reviewCards: [ReportReviewCard]
    let practiceItems: [ReportPracticeItem]

    init(result: SessionResultRead, context: ReportContext = .empty) {
        sessionID = result.session_id
        overallScore = result.overall_score
        title = Self.title(context: context)
        metaText = [context.dateText, context.durationText]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: " · ")
        dimensions = Self.dimensions(from: result)
        reviewCards = Self.reviewCards(from: result.per_question_review)
        practiceItems = Self.practiceItems(from: result.coaching_plan)
    }

    private static func title(context: ReportContext) -> String {
        let prefix = [context.company?.trimmedNonEmpty, context.round?.trimmedNonEmpty]
            .compactMap { $0 }
            .joined()
        return prefix.isEmpty ? "复盘报告" : "\(prefix) · 复盘报告"
    }

    private static func dimensions(from result: SessionResultRead) -> [ReportDimension] {
        if let typed = result.dimensions, !typed.isEmpty {
            return typed.map {
                ReportDimension(
                    key: $0.key,
                    label: $0.label,
                    score: normalizedScore($0.score),
                    isWeakest: $0.is_weakest || result.weakest_dimension == $0.key
                )
            }
        }

        let rows = result.dimension_scores
            .sorted { $0.key < $1.key }
            .map { key, value in
                ReportDimension(
                    key: key,
                    label: key.replacingOccurrences(of: "_", with: " "),
                    score: normalizedScore(score(from: value)),
                    isWeakest: result.weakest_dimension == key
                )
            }
        if rows.contains(where: \.isWeakest) {
            return rows
        }
        guard let weakest = rows.min(by: { $0.score < $1.score }) else { return rows }
        return rows.map {
            ReportDimension(key: $0.key, label: $0.label, score: $0.score, isWeakest: $0.key == weakest.key)
        }
    }

    private static func score(from value: JSONValue) -> Int {
        if case .object(let object) = value {
            return object["score"]?.intValue ?? 0
        }
        return value.intValue ?? 0
    }

    private static func normalizedScore(_ score: Int) -> Int {
        max(0, min(score <= 10 ? score * 10 : score, 100))
    }

    private static func reviewCards(from values: [[String: JSONValue]]) -> [ReportReviewCard] {
        values.enumerated().compactMap { offset, item in
            let question = firstText(item, keys: ["question", "question_text", "prompt"])
            guard let question else { return nil }
            let score = firstText(item, keys: ["score", "points"]).map { "Q\(offset + 1) · \($0)" }
            return ReportReviewCard(
                index: offset + 1,
                question: question,
                scoreText: score,
                answer: firstText(item, keys: ["answer", "candidate_answer", "your_answer"]),
                betterAnswer: firstText(item, keys: ["better_answer", "improved_answer", "suggestion", "better_approach"])
            )
        }
    }

    private static func practiceItems(from plan: [String: JSONValue]) -> [ReportPracticeItem] {
        if case .array(let items)? = plan["items"] {
            return items.compactMap { value in
                guard case .object(let object) = value,
                      let title = firstText(object, keys: ["title", "name"])
                else { return nil }
                let duration = firstText(object, keys: ["duration", "duration_text", "duration_minutes"]).map { value in
                    value.contains("分钟") ? value : "\(value) 分钟"
                }
                return ReportPracticeItem(
                    title: title,
                    subtitle: firstText(object, keys: ["subtitle", "description", "reason"]),
                    durationText: duration
                )
            }
        }

        if case .array(let items)? = plan["practice_items"] {
            return items.compactMap { value in
                guard case .object(let object) = value,
                      let title = firstText(object, keys: ["title", "name"])
                else { return nil }
                return ReportPracticeItem(
                    title: title,
                    subtitle: firstText(object, keys: ["subtitle", "description", "reason"]),
                    durationText: firstText(object, keys: ["duration", "duration_text"])
                )
            }
        }

        return []
    }

    private static func firstText(_ item: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let text = item[key]?.displayText.trimmedNonEmpty, text != "-" {
                return text
            }
        }
        return nil
    }
}

struct ReportView: View {
    let viewModel: ReportViewModel
    var returnHome: () -> Void = {}
    var startAgain: () -> Void = {}

    init(result: SessionResultRead, context: ReportContext = .empty, returnHome: @escaping () -> Void = {}, startAgain: @escaping () -> Void = {}) {
        self.viewModel = ReportViewModel(result: result, context: context)
        self.returnHome = returnHome
        self.startAgain = startAgain
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                scoreSection
                reviewSection
                practiceSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 38)
        }
        .deepSpaceBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var scoreSection: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text(viewModel.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                if !viewModel.metaText.isEmpty {
                    Text(viewModel.metaText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity)

            ScoreCrystal(score: viewModel.overallScore)
                .frame(width: 214, height: 214)

            VStack(spacing: 18) {
                ForEach(viewModel.dimensions, id: \.key) { dimension in
                    ReportDimensionRow(dimension: dimension)
                }
            }
        }
        .padding(.bottom, 28)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("逐题复盘")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DeepSpaceTheme.primaryText)
            ForEach(viewModel.reviewCards, id: \.index) { card in
                ReviewCardView(card: card)
            }
        }
    }

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("练习计划")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DeepSpaceTheme.primaryText)
            ForEach(Array(viewModel.practiceItems.enumerated()), id: \.offset) { _, item in
                PracticeItemRow(item: item)
            }
            Button("再来一场", action: startAgain)
                .buttonStyle(PrimaryCTAStyle())
                .padding(.top, 176)
            Button("回到首页", action: returnHome)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DeepSpaceTheme.tertiaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
        }
    }
}

private struct ScoreCrystal: View {
    let score: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(DeepSpaceTheme.auroraCyan.opacity(0.12))
                .rotationEffect(.degrees(45))
                .overlay(
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .stroke(DeepSpaceTheme.auroraCyan.opacity(0.42), lineWidth: 1)
                        .rotationEffect(.degrees(45))
                )
                .shadow(color: DeepSpaceTheme.auroraCyan.opacity(0.30), radius: 30)
            VStack(spacing: 12) {
                Text("\(score)")
                    .font(.system(size: 92, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                Text("综合表现")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DeepSpaceTheme.tertiaryText)
            }
        }
    }
}

private struct ReportDimensionRow: View {
    let dimension: ReportDimension

    var body: some View {
        HStack(spacing: 14) {
            Text(dimension.label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DeepSpaceTheme.secondaryText)
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                    Capsule(style: .continuous)
                        .fill(dimension.isWeakest ? DeepSpaceTheme.amber : DeepSpaceTheme.auroraCyan)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(dimension.score, 100))) / 100)
                }
            }
            .frame(height: 5)
            Text("\(dimension.score)")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(dimension.isWeakest ? DeepSpaceTheme.amber : DeepSpaceTheme.primaryText)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

private struct ReviewCardView: View {
    let card: ReportReviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AccentChip(text: "复盘", color: DeepSpaceTheme.reviewGreen)
                Spacer()
                if let scoreText = card.scoreText {
                    Text(scoreText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                }
            }
            Text(card.question)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DeepSpaceTheme.primaryText)
                .lineSpacing(4)
            if let answer = card.answer {
                LabeledReportText(label: "你的回答", text: answer, color: DeepSpaceTheme.secondaryText)
            }
            if let better = card.betterAnswer {
                LabeledReportText(label: "更优思路", text: better, color: DeepSpaceTheme.auroraCyan)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
}

private struct LabeledReportText: View {
    let label: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeepSpaceTheme.tertiaryText)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(color)
                .lineSpacing(5)
        }
    }
}

private struct PracticeItemRow: View {
    let item: ReportPracticeItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .stroke(DeepSpaceTheme.tertiaryText, lineWidth: 1.5)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DeepSpaceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let duration = item.durationText {
                    AccentChip(text: "练习 · \(duration)", color: DeepSpaceTheme.practiceText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
