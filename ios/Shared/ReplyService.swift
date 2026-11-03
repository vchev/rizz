import Foundation

/// Where the app gets reply suggestions from.
///
/// Today the app uses `SampleReplyService`, which returns placeholder replies,
/// because the real reply engine is still being tested. When the backend is
/// hosted, set `AppConfig.replyAPIURL` and the app switches to `HTTPReplyService`.
protocol ReplyService {
    /// True when replies are placeholders, so the app can say so.
    var isSample: Bool { get }
    func suggestReplies(for messages: [ChatMessage], platform: String) async throws -> [ReplySuggestion]
}

enum AppConfig {
    /// The hosted reply endpoint. nil = use sample replies.
    static let replyAPIURL: URL? = nil
    /// How many replies to ask for (matches replies_per_request in config.json).
    static let repliesPerRequest = 3
}

enum ReplyServices {
    static func makeDefault() -> ReplyService {
        if let url = AppConfig.replyAPIURL {
            return HTTPReplyService(endpoint: url)
        }
        return SampleReplyService()
    }
}

// MARK: - Sample replies (until the engine is hosted)

struct SampleReplyService: ReplyService {
    var isSample: Bool { true }

    func suggestReplies(for messages: [ChatMessage], platform: String) async throws -> [ReplySuggestion] {
        try await Task.sleep(nanoseconds: 700_000_000)
        let lastFromThem = messages.last(where: { $0.speaker == .them })?.text ?? ""
        let topic = lastFromThem.isEmpty ? "that" : "\u{201C}\(lastFromThem.prefix(40))\u{201D}"
        let samples = [
            "Sample reply: ok wait, tell me more about \(topic)",
            "Sample reply: haha fair. what are you up to this week?",
            "Sample reply: honestly same. coffee sometime?",
        ]
        return samples.prefix(AppConfig.repliesPerRequest).map { ReplySuggestion(text: $0) }
    }
}

// MARK: - Real backend

/// Calls the hosted reply engine.
///
/// Request (POST, JSON):
///   {"platform": "imessage", "n": 3,
///    "messages": [{"speaker": "them", "text": "..."}, {"speaker": "you", "text": "..."}]}
/// Response (JSON):
///   {"replies": [{"text": "..."}, ...]}
///
/// The API key never lives in the app; the backend holds it.
struct HTTPReplyService: ReplyService {
    var endpoint: URL
    var session: URLSession = .shared
    var isSample: Bool { false }

    struct RequestBody: Encodable {
        var platform: String
        var n: Int
        var messages: [ChatMessage]
    }

    struct ResponseBody: Decodable {
        var replies: [ReplySuggestion]
    }

    enum ServiceError: LocalizedError {
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "The reply server had a problem (code \(code)). Try again."
            }
        }
    }

    func suggestReplies(for messages: [ChatMessage], platform: String) async throws -> [ReplySuggestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(platform: platform, n: AppConfig.repliesPerRequest, messages: messages))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data).replies
    }
}
