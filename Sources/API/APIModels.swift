import Foundation

struct DevUserRequest: Encodable { let external_id: String }
struct DevUserResponse: Decodable { let id: String; let external_id: String }

struct ResumeRead: Decodable {
    let id: String
    let version: Int
    let is_current: Bool
    let raw_text: String
    let created_at: String

    init(
        id: String,
        version: Int,
        is_current: Bool,
        raw_text: String = "",
        created_at: String = ""
    ) {
        self.id = id
        self.version = version
        self.is_current = is_current
        self.raw_text = raw_text
        self.created_at = created_at
    }
}
struct ResumeCreateRequest: Encodable { let raw_text: String }

struct PositionRead: Decodable {
    let id: String
    let title: String
    let company: String?
    let jd_text: String
    let seniority: String?
    let created_at: String

    init(
        id: String,
        title: String,
        company: String?,
        jd_text: String = "",
        seniority: String? = nil,
        created_at: String = ""
    ) {
        self.id = id
        self.title = title
        self.company = company
        self.jd_text = jd_text
        self.seniority = seniority
        self.created_at = created_at
    }
}
struct PositionJdUpdateRequest: Encodable { let jd_text: String }
struct AgentHomeSpeechRequest: Encodable {
    let text: String
    let companion: Companion
}
struct RoundRead: Decodable { let id: String; let round_name: String }

struct SessionCreateRequest: Encodable {
    let position_round_id: String
    let companion: Companion
}
struct ScheduleStartRequest: Encodable { let companion: Companion }
struct SessionRead: Decodable {
    let id: String
    let status: String
    let livekit_room: String?
    let failure_reason: String?
    let total_cost_usd: String?   // Decimal serialized as string; display-only
}

struct JoinResponse: Decodable { let livekit_room: String; let livekit_token: String }

struct HomeVoiceJoinResponse: Decodable, Equatable {
    let session_id: String
    let livekit_room: String
    let livekit_token: String
    let current_context: AgentHomeRead
}

struct SessionResultRead: Decodable, Equatable {
    let session_id: String
    let overall_score: Int
    let dimension_scores: [String: JSONValue]
    let dimensions: [DimensionScoreRead]?
    let weakest_dimension: String?
    let practice_round_id: String?
    let tip: String?
    let per_question_review: [[String: JSONValue]]
    let coaching_plan: [String: JSONValue]
    let is_partial: Bool

    var immediateFocus: String {
        tip
            ?? coaching_plan["immediate_focus"]?.shortListText
            ?? ""
    }

    var nextSessionSuggestion: String {
        coaching_plan["next_session_suggestion"]?.stringValue ?? ""
    }

    var dimensionRows: [(String, String)] {
        dimension_scores
            .sorted { $0.key < $1.key }
            .map { key, value in
                let label = key.replacingOccurrences(of: "_", with: " ")
                return (label, value.stringValue ?? "-")
            }
    }

    var questionSummaries: [String] {
        per_question_review.prefix(3).compactMap { item in
            let weaknesses = item["weaknesses"]?.shortListText
            let strengths = item["strengths"]?.shortListText
            return weaknesses ?? strengths
        }
    }

    init(
        session_id: String,
        overall_score: Int,
        dimension_scores: [String: JSONValue],
        dimensions: [DimensionScoreRead]? = nil,
        weakest_dimension: String? = nil,
        practice_round_id: String? = nil,
        tip: String? = nil,
        per_question_review: [[String: JSONValue]],
        coaching_plan: [String: JSONValue],
        is_partial: Bool
    ) {
        self.session_id = session_id
        self.overall_score = overall_score
        self.dimension_scores = dimension_scores
        self.dimensions = dimensions
        self.weakest_dimension = weakest_dimension
        self.practice_round_id = practice_round_id
        self.tip = tip
        self.per_question_review = per_question_review
        self.coaching_plan = coaching_plan
        self.is_partial = is_partial
    }
}

struct DimensionScoreRead: Decodable, Equatable {
    let key: String
    let label: String
    let score: Int
    let is_weakest: Bool
}

struct ScheduleDraftParseRequest: Encodable {
    let text: String
    let timezone: String
}

indirect enum JSONValue: Decodable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return Bool(value)
        default:
            return nil
        }
    }

    var shortListText: String? {
        switch self {
        case .array(let values):
            let parts = values.compactMap(\.stringValue).filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: "；")
        case .string(let value):
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "是" : "否"
        case .object(let value):
            return value
                .sorted { $0.key < $1.key }
                .map { "\($0.key)：\($0.value.displayText)" }
                .joined(separator: "；")
        case .array(let values):
            return values.map(\.displayText).joined(separator: "；")
        case .null:
            return "-"
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ScheduleDraftRead: Decodable, Identifiable, Equatable {
    let id: String
    let raw_input: String
    let intent: String
    let action: String
    let confidence: Double
    let assistant_message: String
    let position_round_id: String?
    let scheduled_at: String?
    let missing_fields: [String]
    let validation_errors: [String]
    let ambiguities: [String]
    let pull_back_message: String?
    let suggested_replies: [String]
    let normalized_slots: [String: JSONValue]?
    let status: String
    let expires_at: String
    let created_at: String

    var displayMessage: String {
        pull_back_message ?? assistant_message
    }

    var isConfirmable: Bool {
        action == "confirm" && status == "confirmable"
    }
}

struct InterviewScheduleRead: Decodable, Identifiable, Equatable {
    let id: String
    let position_round_id: String
    let scheduled_at: String
    let timezone: String
    let duration_minutes: Int
    let status: String
    let session_id: String?
    let raw_command: String
    let created_at: String
    let position_title: String?
    let company: String?
    let round_name: String?

    init(
        id: String,
        position_round_id: String,
        scheduled_at: String,
        timezone: String,
        duration_minutes: Int,
        status: String,
        session_id: String?,
        raw_command: String,
        created_at: String,
        position_title: String? = nil,
        company: String? = nil,
        round_name: String? = nil
    ) {
        self.id = id
        self.position_round_id = position_round_id
        self.scheduled_at = scheduled_at
        self.timezone = timezone
        self.duration_minutes = duration_minutes
        self.status = status
        self.session_id = session_id
        self.raw_command = raw_command
        self.created_at = created_at
        self.position_title = position_title
        self.company = company
        self.round_name = round_name
    }
}

struct InterviewScheduleList: Decodable {
    let schedules: [InterviewScheduleRead]
}

struct ScheduleDetailRead: Decodable {
    let schedule: InterviewScheduleRead
    let position: PositionRead
    let round: RoundRead
    let resume: ResumeRead?
}

struct InterviewScheduleUpdateRequest: Encodable {
    let scheduled_at: String?
    let timezone: String?
    let duration_minutes: Int?
}

struct ScheduleStartRead: Decodable {
    let schedule: InterviewScheduleRead
    let session: SessionRead
}

enum AgentHomeActionType: String, Codable, Equatable {
    case createTarget = "create_target"
    case addJD = "add_jd"
    case createSchedule = "create_schedule"
    case startPractice = "start_practice"
    case resumeLiveSession = "resume_live_session"
    case reviewResult = "review_result"
    case practiceWeakness = "practice_weakness"
    case waitScoring = "wait_scoring"
    case quickStart = "quick_start"
}

struct AgentHomeRead: Decodable, Equatable {
    let generated_at: String
    let primary_action: AgentHomePrimaryAction
    let signals: [AgentHomeSignal]
    let voice_suggestions: [String]
    let briefing_items: [AgentHomeBriefingItem]?
    // Voice-context fields (2026-06-11 concierge pipeline fix) — all optional so
    // old payloads still decode; consumed server-side, decoded here for parity.
    let timezone: String?
    let round_candidates: [HomeRoundCandidate]?
    let recent_schedule: HomeScheduleRef?
    let last_scored_session_id: String?

    init(
        generated_at: String,
        primary_action: AgentHomePrimaryAction,
        signals: [AgentHomeSignal],
        voice_suggestions: [String],
        briefing_items: [AgentHomeBriefingItem]?,
        timezone: String? = nil,
        round_candidates: [HomeRoundCandidate]? = nil,
        recent_schedule: HomeScheduleRef? = nil,
        last_scored_session_id: String? = nil
    ) {
        self.generated_at = generated_at
        self.primary_action = primary_action
        self.signals = signals
        self.voice_suggestions = voice_suggestions
        self.briefing_items = briefing_items
        self.timezone = timezone
        self.round_candidates = round_candidates
        self.recent_schedule = recent_schedule
        self.last_scored_session_id = last_scored_session_id
    }
}

struct HomeRoundCandidate: Decodable, Equatable {
    let id: String
    let position_id: String
    let company: String
    let title: String
    let round_name: String
    let round_number: Int
}

struct HomeScheduleRef: Decodable, Equatable {
    let schedule_id: String
    let position_id: String?
    let position_round_id: String?
    let company: String?
    let round_name: String?
    let scheduled_at: String?
}

struct AgentHomePrimaryAction: Decodable, Equatable {
    let type: String
    let title: String
    let spoken_prompt: String
    let reason: String
    let cta: String
    let target: [String: String]
}

struct AgentHomeSignal: Decodable, Equatable {
    let type: String
    let label: String
    let severity: String
}

struct AgentHomeBriefingItem: Decodable, Equatable {
    let source: String
    let action_type: String
    let target: [String: String]
    let title: String
    let reason: String
    let cta: String
    let emphasis: Bool
}
