import Foundation

/// Decoded backend error envelope (see docs/api/CLIENT_INTEGRATION.md §2).
struct APIError: Error, Codable, Equatable {
    let status: Int
    let errorCode: String
    let userMessage: String
    let traceId: String?
    let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case errorCode = "error_code"
        case userMessage = "user_message"
        case traceId = "trace_id"
        case retryAfter = "retry_after"
    }
}

/// Fallback for transport/non-envelope failures.
struct TransportError: Error, Equatable { let message: String }

struct ResumeRequiredError: Error, Equatable, CustomStringConvertible {
    let description = "请先在设置中添加真实简历，再开始面试。"
}
