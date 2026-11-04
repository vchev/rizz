import Foundation

/// Where the app gets reply suggestions from.
///
/// Today the app uses `SampleReplyService`, which returns placeholder replies,
/// because the real reply engine is still being tested. When the backend is
/// hosted, set `AppConfig.replyAPIURL` and the app switches to `HTTPReplyService`.
protocol ReplyService {
    /// True when replies are placeholders, so the app can say so.
    var isSample: Bool { get }
    /// `replyingTo`: the message the user has started a quoted reply to, if any.
    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?,
                        replyingTo: String?) async throws -> [ReplySuggestion]
}

extension ReplyService {
    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?) async throws -> [ReplySuggestion] {
        try await suggestReplies(for: messages, platform: platform, tone: tone, replyingTo: nil)
    }
}

/// Optional nudge for a new set of replies.
enum ReplyTone: String, Codable, CaseIterable, Identifiable {
    case funnier, flirtier, shorter
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AppConfig {
    /// The hosted reply endpoint. nil = use sample replies.
    static let replyAPIURL: URL? = URL(string: "https://rizz-olive.vercel.app/api/reply")
    /// Sent as X-Coax-Token so only the app can use the endpoint. Read from the
    /// CoaxAppToken Info.plist value, set from ios/Secrets.xcconfig (git-ignored).
    /// Anyone with the app can read it, so it's a speed bump; rotate before launch.
    static var replyAPIToken: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CoaxAppToken") as? String
        return (value?.isEmpty ?? true) ? nil : value
    }
    /// How many replies to ask for (matches replies_per_request in config.json).
    static let repliesPerRequest = 3
    /// The ready-made Back Tap shortcut (Take Screenshot, then Get Coax Replies),
    /// shared from iCloud. nil until it's made; the app then shows the steps instead.
    static let backTapShortcutLink: URL? = nil
}

enum ReplyServices {
    static func makeDefault() -> ReplyService {
        // UI tests use sample replies, so they don't depend on the server.
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if !uiTesting, let url = AppConfig.replyAPIURL {
            return HTTPReplyService(endpoint: url, token: AppConfig.replyAPIToken)
        }
        return SampleReplyService()
    }
}

// MARK: - Sample replies (until the engine is hosted)

struct SampleReplyService: ReplyService {
    var isSample: Bool { true }

    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?,
                        replyingTo: String?) async throws -> [ReplySuggestion] {
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
///    "under_18": true,                                   // teen mode only
///    "voice": {"length": 0.2, ..., "examples": ["..."]}, // only when the voice profile is on
///    "messages": [{"speaker": "them", "text": "..."}, {"speaker": "you", "text": "..."}]}
/// Response (JSON):
///   {"replies": [{"text": "..."}, ...]}
///
/// The API key never lives in the app; the backend holds it.
struct HTTPReplyService: ReplyService {
    var endpoint: URL
    var token: String? = nil
    var session: URLSession = .shared
    var isSample: Bool { false }

    struct RequestBody: Encodable {
        var platform: String
        var n: Int
        var tone: ReplyTone?
        /// Teen mode (ages 16-17): the engine keeps replies free of sexual content.
        var under18: Bool? = nil
        var messages: [ChatMessage]
        var replyingTo: String?
        /// The user's voice profile (Sprint 3 preview). Left out when it's off.
        var voice: VoiceProfile.Payload? = nil

        enum CodingKeys: String, CodingKey {
            case platform, n, tone, messages, voice
            case under18 = "under_18"
            case replyingTo = "replying_to"
        }
    }

    struct ResponseBody: Decodable {
        var replies: [ReplySuggestion]
    }

    struct ErrorBody: Decodable {
        var error: String
    }

    enum ServiceError: LocalizedError {
        case badStatus(Int)
        case server(String)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "The reply server had a problem (code \(code)). Try again."
            case .server(let message): return message
            }
        }
    }

    func suggestReplies(for messages: [ChatMessage], platform: String, tone: ReplyTone?,
                        replyingTo: String?) async throws -> [ReplySuggestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Coax-Token") }
        request.httpBody = try JSONEncoder().encode(
            RequestBody(platform: platform, n: AppConfig.repliesPerRequest, tone: tone,
                        under18: AgeSettings.wantsTeenReplies ? true : nil, messages: messages,
                        replyingTo: replyingTo,
                        voice: VoiceSettings.voiceForRequest(learningFrom: messages)))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 {
                throw ServiceError.server("This copy of Coax is missing its app password (ios/Secrets.xcconfig). Add it, then Clean Build Folder and run again.")
            }
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), !body.error.isEmpty {
                throw ServiceError.server(body.error)
            }
            throw ServiceError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data).replies
    }
}
