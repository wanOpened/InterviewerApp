import Foundation

enum InterviewVoiceCommand: Equatable {
    case pause
    case resume
    case end
}

enum VoiceCommandInterpreter {
    static func interviewCommand(from rawText: String) -> InterviewVoiceCommand? {
        let text = normalized(rawText)
        guard text.count <= 14 else { return nil }

        if containsAny(text, ["暂停面试", "先暂停", "暂停一下", "停一下"]) {
            return .pause
        }
        if containsAny(text, ["继续面试", "继续吧", "恢复面试", "开始继续"]) {
            return .resume
        }
        if containsAny(text, ["结束面试", "退出面试", "离开房间", "停止面试"]) {
            return .end
        }
        return nil
    }

    private static func normalized(_ rawText: String) -> String {
        rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "青岚", with: "")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
