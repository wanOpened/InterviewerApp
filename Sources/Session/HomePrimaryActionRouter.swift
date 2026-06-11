import Foundation

enum HomeInterviewLaunch: Equatable {
    case resume(sessionId: String)
    case startSchedule(scheduleId: String)
    case startRound(positionRoundId: String)
}

enum HomePrimaryActionRoute: Equatable {
    case interview(HomeInterviewLaunch)
    case voice
}

struct HomePrimaryActionPresentation: Equatable {
    let title: String
    let accessory: String

    static func make(action: AgentHomePrimaryAction?, nextScheduleID: String?) -> HomePrimaryActionPresentation? {
        guard let action else { return nil }
        guard !duplicatesSchedulePeek(action: action, nextScheduleID: nextScheduleID) else {
            return nil
        }
        return HomePrimaryActionPresentation(title: action.title, accessory: "chevron.right")
    }

    private static func duplicatesSchedulePeek(action: AgentHomePrimaryAction, nextScheduleID: String?) -> Bool {
        guard let nextScheduleID else { return false }
        if action.target["schedule_id"] == nextScheduleID {
            return true
        }
        if action.target["schedule_id"] != nil {
            return false
        }
        guard action.type == AgentHomeActionType.startPractice.rawValue else {
            return false
        }
        return [action.title, action.cta, action.reason]
            .contains { $0.contains("准备") }
    }
}

enum HomePrimaryActionRouter {
    static func route(for action: AgentHomePrimaryAction) -> HomePrimaryActionRoute {
        switch action.type {
        case AgentHomeActionType.resumeLiveSession.rawValue:
            if let sessionId = action.target["session_id"] {
                return .interview(.resume(sessionId: sessionId))
            }
        case AgentHomeActionType.startPractice.rawValue,
             AgentHomeActionType.quickStart.rawValue:
            if let sessionId = action.target["session_id"] {
                return .interview(.resume(sessionId: sessionId))
            }
            if let scheduleId = action.target["schedule_id"] {
                return .interview(.startSchedule(scheduleId: scheduleId))
            }
            if let roundId = action.target["position_round_id"] {
                return .interview(.startRound(positionRoundId: roundId))
            }
        case AgentHomeActionType.practiceWeakness.rawValue:
            if let sessionId = action.target["session_id"] {
                return .interview(.resume(sessionId: sessionId))
            }
            if let roundId = action.target["position_round_id"] {
                return .interview(.startRound(positionRoundId: roundId))
            }
        default:
            break
        }
        return .voice
    }
}
