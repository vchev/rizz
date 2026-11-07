import Foundation

/// One thing the voice profile tracks. Each is a slider from 0 to 1.
enum VoiceTrait: String, Codable, CaseIterable, Identifiable {
    // Quiz order: how you write first, then how you flirt.
    case length, caps, emoji, humour, forward, looking
    var id: String { rawValue }

    /// The quiz question, one per screen.
    var question: String {
        switch self {
        case .length: return "Do you send quick texts or full paragraphs?"
        case .caps: return "Are you all lowercase, or capitals and full stops?"
        case .emoji: return "How often do you use emoji?"
        case .humour: return "Do you keep it sincere, or tease and joke?"
        case .forward: return "When you like someone, do you play it cool or say it?"
        case .looking: return "What are you looking for right now?"
        }
    }

    /// Short name for the style card.
    var name: String {
        switch self {
        case .length: return "Message length"
        case .caps: return "Capital letters"
        case .emoji: return "Emoji"
        case .humour: return "Humour"
        case .forward: return "When you like someone"
        case .looking: return "Looking for"
        }
    }

    /// Words at the 0 end and the 1 end of the slider.
    var ends: (low: String, high: String) {
        switch self {
        case .length: return ("quick texts ⚡️", "full paragraphs 📝")
        case .caps: return ("all lowercase 😎", "Proper Sentences. ✍️")
        case .emoji: return ("rarely 🙂", "all the time 😂")
        case .humour: return ("sincere 🤍", "teasing 😏")
        case .forward: return ("play it cool 🧊", "say it 💬")
        case .looking: return ("something casual 🍸", "a relationship 💞")
        }
    }

    /// A chip for the style card, or nil when the value is in the middle.
    func chip(_ value: Double) -> String? {
        switch (self, value <= 1.0 / 3, value >= 2.0 / 3) {
        case (.length, true, _): return "short replies"
        case (.length, _, true): return "longer messages"
        case (.caps, true, _): return "mostly lowercase"
        case (.caps, _, true): return "proper capitals"
        case (.humour, true, _): return "sincere"
        case (.humour, _, true): return "dry humour"
        case (.emoji, true, _): return "rare emoji"
        case (.emoji, _, true): return "emoji fan"
        case (.forward, true, _): return "plays it cool"
        case (.forward, _, true): return "says what they feel"
        case (.looking, true, _): return "keeping it casual"
        case (.looking, _, true): return "wants something real"
        default: return nil
        }
    }

    /// Whether Coax can measure this from the user's own messages.
    var isMeasured: Bool { self == .length || self == .caps || self == .emoji }

}

/// The user's voice profile ("Your texting style"), kept on the phone only.
///
/// It starts from a 5-slider quiz, then the user's own messages (right-hand
/// bubbles) in the screenshots they take for replies tune it. Nothing is
/// uploaded: each reply request sends the slider values and a few of the
/// user's own recent texts, and the server keeps neither.
struct VoiceProfile: Codable, Equatable {
    /// Quiz answers, 0...1, keyed by VoiceTrait raw value. Empty = quiz not taken.
    var quiz: [String: Double] = [:]
    /// When true, the user chose "Go back to my quiz": learned values are ignored.
    var trustQuiz = false

    // What Coax has learned from the user's own messages.
    var messageCount = 0
    var wordCount = 0
    var capitalStarts = 0
    var letterStarts = 0
    var emojiMessages = 0
    /// The user's most recent own messages, newest last, for few-shot examples.
    var recent: [String] = []
    /// Normalised texts already counted, so overlapping screenshots never count twice.
    var seen: [String] = []

    static let maxRecent = 30
    static let maxSeen = 600
    static let examplesSent = 8
    /// Learned values take over gradually: full weight (80%) after this many messages.
    static let messagesForFullWeight = 40.0
    /// Below this many messages the card says "still learning".
    static let confidentAt = 20

    var hasQuiz: Bool { !quiz.isEmpty }

    /// What the user's messages say, or nil when there aren't enough yet.
    func learned(_ trait: VoiceTrait) -> Double? {
        guard messageCount >= 5 else { return nil }
        switch trait {
        case .length:
            let avg = Double(wordCount) / Double(messageCount)
            return min(max((avg - 3) / 17, 0), 1)          // 3 words or fewer = 0, 20+ = 1
        case .caps:
            guard letterStarts > 0 else { return nil }
            return Double(capitalStarts) / Double(letterStarts)
        case .emoji:
            return min(Double(emojiMessages) / Double(messageCount) * 2, 1)   // half the texts = 1
        case .humour, .forward, .looking:
            return nil
        }
    }

    /// The value used for replies: the quiz answer, moved toward what the messages show.
    func value(_ trait: VoiceTrait) -> Double {
        // Not asked in the quiz (length, capitals, emoji): the texts alone decide.
        if quiz[trait.rawValue] == nil, !trustQuiz, let seen = learned(trait) { return seen }
        let answer = quiz[trait.rawValue] ?? 0.5
        guard !trustQuiz, let seen = learned(trait) else { return answer }
        let weight = min(Double(messageCount) / Self.messagesForFullWeight, 1) * 0.8
        return answer * (1 - weight) + seen * weight
    }

    var chips: [String] { shownTraits.compactMap { $0.chip(value($0)) } }

    /// Traits with something to show: a quiz answer or enough of the user's texts.
    var shownTraits: [VoiceTrait] {
        VoiceTrait.allCases.filter { quiz[$0.rawValue] != nil || learned($0) != nil }
    }

    /// A one-line summary for the top of the style card.
    var headline: String {
        var words: [String] = []
        if value(.length) <= 1.0 / 3 { words.append("short") } else if value(.length) >= 2.0 / 3 { words.append("chatty") }
        if value(.caps) <= 1.0 / 3 { words.append("lowercase") }
        if value(.humour) >= 2.0 / 3 { words.append("quietly funny") } else if value(.humour) <= 1.0 / 3 { words.append("sincere") }
        if value(.forward) >= 2.0 / 3 { words.append("upfront") } else if value(.forward) <= 1.0 / 3 { words.append("cool") }
        guard !words.isEmpty else { return "Easygoing and balanced" }
        let line = words.prefix(3).joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// The biggest gap between the quiz and the user's real texts, once Coax is confident.
    /// For example "You text shorter than you said".
    var surprise: String? {
        guard hasQuiz, !trustQuiz, messageCount >= Self.confidentAt else { return nil }
        let gaps = VoiceTrait.allCases.compactMap { trait -> (VoiceTrait, Double)? in
            guard let answer = quiz[trait.rawValue], let seen = learned(trait) else { return nil }
            return abs(seen - answer) >= 0.25 ? (trait, seen - answer) : nil
        }
        guard let (trait, gap) = gaps.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        switch (trait, gap < 0) {
        case (.length, true): return "You text shorter than you said"
        case (.length, false): return "You text longer than you said"
        case (.caps, true): return "You use fewer capitals than you said"
        case (.caps, false): return "You use more capitals than you said"
        case (.emoji, true): return "You use fewer emoji than you said"
        case (.emoji, false): return "You use more emoji than you said"
        default: return nil
        }
    }

    /// "Keep it": make the quiz match what the messages show.
    mutating func acceptLearned() {
        for trait in VoiceTrait.allCases { if let seen = learned(trait) { quiz[trait.rawValue] = seen } }
        trustQuiz = false
    }

    /// Count the user's own messages. Returns how many were new.
    @discardableResult
    mutating func learn(from messages: [ChatMessage], ignoring ignored: Set<String> = []) -> Int {
        var added = 0
        for message in messages where message.speaker == .you {
            let text = message.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = Transcript.normalized(text)
            guard key.count >= 2, !ignored.contains(key), !seen.contains(key) else { continue }
            seen.append(key)
            messageCount += 1
            wordCount += text.split(separator: " ").count
            if let first = text.first(where: { $0.isLetter }) {
                letterStarts += 1
                if first.isUppercase { capitalStarts += 1 }
            }
            if text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { emojiMessages += 1 }
            recent.append(text)
            added += 1
        }
        if seen.count > Self.maxSeen { seen.removeFirst(seen.count - Self.maxSeen) }
        if recent.count > Self.maxRecent { recent.removeFirst(recent.count - Self.maxRecent) }
        return added
    }

    /// What goes to the reply engine, or nil when there's nothing useful to send.
    var payload: Payload? {
        guard hasQuiz || messageCount > 0 else { return nil }
        func v(_ t: VoiceTrait) -> Double? {
            (quiz[t.rawValue] != nil || learned(t) != nil) ? (value(t) * 100).rounded() / 100 : nil
        }
        return Payload(length: v(.length), caps: v(.caps), humour: v(.humour), emoji: v(.emoji),
                       forward: v(.forward), looking: v(.looking), examples: Array(recent.suffix(Self.examplesSent)))
    }

    /// The "voice" field of a reply request.
    struct Payload: Codable, Equatable {
        var length: Double?
        var caps: Double?
        var humour: Double?
        var emoji: Double?
        var forward: Double?
        var looking: Double?
        var examples: [String]
    }
}

/// Where the voice profile is saved, and whether replies use it.
///
/// Sprint 3 preview: off until the user turns it on (test builds show a
/// "Voice" button on the main screen). Off = requests are exactly as before.
enum VoiceSettings {
    private static let profileKey = "coax.voiceProfile"
    private static let enabledKey = "coax.voiceEnabled"
    private static let learningKey = "coax.voiceLearning"

    static var defaults: UserDefaults { AgeSettings.defaults }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// "Learn from what I send": on unless the user turned it off.
    static var isLearning: Bool {
        get { defaults.object(forKey: learningKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: learningKey) }
    }

    static var profile: VoiceProfile {
        get {
            guard let data = defaults.data(forKey: profileKey),
                  let saved = try? JSONDecoder().decode(VoiceProfile.self, from: data) else { return VoiceProfile() }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: profileKey) }
    }

    /// The made-up example chat must never teach Coax how the user texts.
    static var ignoredTexts: Set<String> {
        Set(ChatMessage.example.map { Transcript.normalized($0.text) })
    }

    /// Called with every chat sent for replies: learns from the user's own
    /// messages (when allowed) and returns the voice to send, or nil when off.
    static func voiceForRequest(learningFrom messages: [ChatMessage]) -> VoiceProfile.Payload? {
        guard isEnabled else { return nil }
        var current = profile
        if isLearning, current.learn(from: messages, ignoring: ignoredTexts) > 0 { profile = current }
        return current.payload
    }

    static func reset() {
        for key in [profileKey, enabledKey, learningKey] { defaults.removeObject(forKey: key) }
    }
}

/// What the person does with replies, counted on the phone only: the PRD's
/// usage numbers without any analytics service, plus the mood they pick most,
/// so the next replies can lean that way. Nothing here is uploaded except the
/// favorite mood's one word, sent with a reply request.
struct ReplyHabits: Codable, Equatable {
    /// Chats read from screenshots.
    var reads = 0
    /// Sets of replies shown.
    var replySets = 0
    /// New replies asked for when a set was already showing (a tag or "Get new replies").
    var askedAgain = 0
    /// Replies typed in or copied.
    var picks = 0
    /// Picks by the reply's mood label ("playful": 4).
    var moodPicks: [String: Int] = [:]

    /// Picks needed before Coax leans toward a favorite mood.
    static let minPicks = 5
    /// The favorite must be at least this share of picks.
    static let minShare = 0.4

    /// The mood picked most, once there's a clear one.
    var favoriteMood: String? {
        guard picks >= Self.minPicks,
              let top = moodPicks.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first,
              Double(top.value) / Double(picks) >= Self.minShare else { return nil }
        return top.key
    }

    mutating func pick(_ reply: ReplySuggestion) {
        picks += 1
        if let mood = reply.label?.lowercased().trimmingCharacters(in: .whitespaces), !mood.isEmpty {
            moodPicks[mood, default: 0] += 1
        }
    }

    /// Share of reply sets where one was picked (the PRD's "would send" rate, roughly).
    var pickRate: Double? { replySets > 0 ? Double(picks) / Double(replySets) : nil }
}

/// Where ReplyHabits is kept: this part of Coax's own settings on the phone.
enum HabitStore {
    private static let key = "coax.replyHabits"
    static var defaults: UserDefaults { AgeSettings.defaults }
    /// UI tests start clean and leave nothing behind.
    static var isOff: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    static var current: ReplyHabits {
        guard !isOff, let data = defaults.data(forKey: key),
              let habits = try? JSONDecoder().decode(ReplyHabits.self, from: data) else { return ReplyHabits() }
        return habits
    }

    static func update(_ change: (inout ReplyHabits) -> Void) {
        guard !isOff else { return }
        var habits = current
        change(&habits)
        if let data = try? JSONEncoder().encode(habits) { defaults.set(data, forKey: key) }
    }
}
