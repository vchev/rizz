import Foundation

/// One chat with one match, as Coax has read it so far.
struct SavedChat: Codable, Identifiable, Equatable {
    var id: String
    var messages: [ChatMessage]
    var updated: Date
}

/// Keeps each match's chat on the phone, so a new screenshot adds to what
/// Coax already read instead of starting over, and replies can use the
/// earlier part of the chat too.
///
/// A new read joins a saved chat when they share messages (or when the
/// caller passes the same `key`, like the Messages conversation). Nothing
/// leaves the phone; chats untouched for 30 days are forgotten.
///
/// Each part of Coax (app, keyboard, Messages app) keeps its own file:
/// sharing one needs an App Group, which free Apple sign-in can't use.
final class ChatStore {
    static let maxChats = 40
    static let maxMessagesPerChat = 300
    static let keepFor: TimeInterval = 30 * 24 * 3600

    /// The file in this app or extension's own storage.
    static let shared: ChatStore = {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return ChatStore(url: dir.appendingPathComponent("coax-chats.json"))
    }()

    /// The store to use, or nil in UI tests so runs start clean.
    static var forUse: ChatStore? {
        ProcessInfo.processInfo.arguments.contains("-uiTesting") ? nil : shared
    }

    let url: URL
    private(set) var chats: [SavedChat] = []

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([SavedChat].self, from: data) {
            chats = saved
        }
    }

    /// Adds newly read messages to the chat they belong to (or starts a new one)
    /// and returns that chat. Speakers someone fixed by hand are kept.
    @discardableResult
    func remember(_ read: [ChatMessage], key: String? = nil, now: Date = Date()) -> SavedChat {
        chats.removeAll { now.timeIntervalSince($0.updated) > Self.keepFor }
        var chat: SavedChat
        if let index = bestMatch(for: read, key: key) {
            chat = chats.remove(at: index)
            chat.messages = Self.join(chat.messages, read)
        } else {
            chat = SavedChat(id: key ?? UUID().uuidString, messages: read, updated: now)
        }
        chat.updated = now
        chat.messages = Array(chat.messages.suffix(Self.maxMessagesPerChat))
        chats.insert(chat, at: 0)
        chats = Array(chats.prefix(Self.maxChats))
        save()
        return chat
    }

    /// Saves edits (a speaker switched, a line removed) to a chat.
    func update(_ id: String, messages: [ChatMessage], now: Date = Date()) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[i].messages = messages
        chats[i].updated = now
        save()
    }

    func chat(_ id: String) -> SavedChat? { chats.first { $0.id == id } }

    func forgetAll() {
        chats = []
        try? FileManager.default.removeItem(at: url)
    }

    /// The saved chat these messages belong to, if any.
    private func bestMatch(for read: [ChatMessage], key: String?) -> Int? {
        if let key, let i = chats.firstIndex(where: { $0.id == key }) { return i }
        guard key == nil else { return nil }
        // Most recently used chats first, so a match there wins.
        return chats.firstIndex { Self.belongTogether($0.messages, read) }
    }

    /// Enough shared messages that it's surely the same chat: two in a row or
    /// one long one, with at least 20 letters between them (so "hey" + "lol"
    /// from two different people don't count). Speakers aren't compared, since
    /// they may have been fixed by hand.
    static func belongTogether(_ saved: [ChatMessage], _ read: [ChatMessage]) -> Bool {
        func enough(_ shared: ArraySlice<ChatMessage>) -> Bool {
            let letters = shared.reduce(0) { $0 + Transcript.normalized($1.text).count }
            return (shared.count >= 2 && letters >= 20) || letters >= 25
        }
        if Transcript.contains(saved, read) { return enough(read[...]) }
        let after = Transcript.overlap(saved, then: read, matchSpeaker: false)
        if after > 0 && enough(read.prefix(after)) { return true }
        let before = Transcript.overlap(read, then: saved, matchSpeaker: false)
        return before > 0 && enough(saved.prefix(before))
    }

    /// The saved chat with the new read added where it fits.
    static func join(_ saved: [ChatMessage], _ read: [ChatMessage]) -> [ChatMessage] {
        if Transcript.contains(saved, read) { return saved }
        let after = Transcript.overlap(saved, then: read, matchSpeaker: false)
        let before = Transcript.overlap(read, then: saved, matchSpeaker: false)
        if before > after {
            // Scrolled up past what was saved: the new part goes first, and the
            // saved copies (with any fixed speakers) win for the shared messages.
            return Transcript.merge(read, then: saved, overlapping: before, speakersFrom: .next)
        }
        return Transcript.merge(saved, then: read, overlapping: after, speakersFrom: .earlier)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
