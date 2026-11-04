import Foundation

/// Where the app gets reply suggestions from.
///
/// Today the app uses `SampleReplyService`, which returns placeholder replies,
/// because the real reply engine is still being tested. When the backend is
/// hosted, set `AppConfig.replyAPIURL` and the app switches to `HTTPReplyService`.
protocol ReplyService {
    /// True when replies are placeholders, so the app can say so.
    var isSample: Bool { get }
    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?) async throws -> [ReplySuggestion]
}

/// Optional nudge for a new set of replies.
enum ReplyTone: String, Codable, CaseIterable, Identifiable {
    case funnier, flirtier, shorter
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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

    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?) async throws -> [ReplySuggestion] {
        try await Task.sleep(nanoseconds: 700_000_000)
        let samples: [String]
        switch tone {
        case .funnier:
            samples = ["Sample (funnier): ok that is unhinged and I respect it",
                       "Sample (funnier): bold of you to say that before our first date",
                       "Sample (funnier): I'm telling my mom about this"]
        case .flirtier:
            samples = ["Sample (flirtier): you're kind of making it hard to play it cool",
                       "Sample (flirtier): tell me more over a drink?",
                       "Sample (flirtier): ok you're cute when you say things like that"]
        case .shorter:
            samples = ["Sample (shorter): haha yes", "Sample (shorter): tell me more", "Sample (shorter): coffee?"]
        case nil:
            samples = ["Sample reply: ok wait, tell me more",
                       "Sample reply: haha fair. what are you up to this week?",
                       "Sample reply: honestly same. coffee sometime?"]
        }
        return samples.prefix(AppConfig.repliesPerRequest).map { ReplySuggestion(text: $0) }
    }
}

// MARK: - Real backend

/// Calls the hosted reply engine.
///
/// Request (POST, JSON):
///   {"platform": "imessage", "n": 3, "tone": "funnier",   // tone is optional
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
        var tone: ReplyTone?
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

    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?) async throws -> [ReplySuggestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(platform: platform, n: AppConfig.repliesPerRequest, tone: tone, messages: messages))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data).replies
    }
}
