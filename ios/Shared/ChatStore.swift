import Foundation

/// One chat with one match, as Coax has read it so far.
struct SavedChat: Codable, Identifiable, Equatable {
    var id: String
    var messages: [ChatMessage]
    var updated: Date
    /// Where the most recent screenshot's messages sit in `messages`.
    var latest: Range<Int>? = nil
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
        lastJoin = nil
        if let index = bestMatch(for: read, key: key) {
            chat = chats.remove(at: index)
            lastJoin = (chat, read)
            let joined = Self.join(chat.messages, read)
            chat.messages = joined.messages
            chat.latest = joined.latest
        } else {
            chat = SavedChat(id: key ?? UUID().uuidString, messages: read, updated: now, latest: 0..<read.count)
        }
        chat.updated = now
        let dropped = max(chat.messages.count - Self.maxMessagesPerChat, 0)
        chat.messages = Array(chat.messages.suffix(Self.maxMessagesPerChat))
        if let latest = chat.latest {
            chat.latest = max(latest.lowerBound - dropped, 0)..<max(latest.upperBound - dropped, 0)
        }
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

    /// The chat as it was before the last `remember` joined a read into it.
    private var lastJoin: (before: SavedChat, read: [ChatMessage])?

    /// "Wrong chat? Start fresh": undoes the last join (the saved chat goes back
    /// to how it was) and keeps the latest read as a chat of its own.
    @discardableResult
    func startFresh(_ id: String, now: Date = Date()) -> SavedChat? {
        guard let join = lastJoin, join.before.id == id,
              let i = chats.firstIndex(where: { $0.id == id }) else { return nil }
        lastJoin = nil
        let isKeyed = id.hasPrefix("messages:")
        if isKeyed {
            chats.remove(at: i)            // a keyed chat can't be split; it's just replaced
        } else {
            chats[i] = join.before
        }
        let fresh = SavedChat(id: isKeyed ? id : UUID().uuidString, messages: join.read, updated: now,
                              latest: 0..<join.read.count)
        chats.insert(fresh, at: 0)
        save()
        return fresh
    }

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

    /// Enough shared messages that it's surely the same chat: two or one long
    /// one, with at least 20 letters between them (so "hey" + "lol" from two
    /// different people don't count). Speakers aren't compared, since they may
    /// have been fixed by hand.
    static func belongTogether(_ saved: [ChatMessage], _ read: [ChatMessage]) -> Bool {
        let shared = matches(saved, read).map { read[$0.read] }
        let letters = shared.reduce(0) { $0 + Transcript.normalized($1.text).count }
        // A real overlap is a good part of the new screenshot, not one stray line.
        guard shared.count * 4 >= min(read.count, 12) else { return false }
        return (shared.count >= 2 && letters >= 20) || letters >= 40
    }

    /// Pairs of (saved index, read index) for the same message, in order: the
    /// longest run of matches, allowing misreads and messages that only one
    /// side has (a timestamp read as text, a bubble cut off at the edge).
    static func matches(_ saved: [ChatMessage], _ read: [ChatMessage]) -> [(saved: Int, read: Int)] {
        // Short messages ("lol", "I'm in") repeat in any chat, so they only
        // count right next to a longer shared message (see the filter below).
        func isShort(_ a: ChatMessage) -> Bool { Transcript.normalized(a.text).count < 8 }
        func same(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
            if isShort(a) || isShort(b) { return Transcript.normalized(a.text) == Transcript.normalized(b.text) }
            return Transcript.similar(a.text, b.text)
                || Transcript.isCutOff(a.text, of: b.text, keepingEnd: true)
                || Transcript.isCutOff(a.text, of: b.text, keepingEnd: false)
                || Transcript.isCutOff(b.text, of: a.text, keepingEnd: true)
                || Transcript.isCutOff(b.text, of: a.text, keepingEnd: false)
        }
        let n = saved.count, m = read.count
        guard n > 0, m > 0 else { return [] }
        // Longest common subsequence, by fuzzy sameness.
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = same(saved[i], read[j])
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(saved: Int, read: Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if same(saved[i], read[j]) && table[i][j] == table[i + 1][j + 1] + 1 {
                pairs.append((i, j)); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        // Keep short matches only when chained (both sides consecutive) to a long one.
        var keep = pairs.map { !isShort(saved[$0.saved]) && !isShort(read[$0.read]) }
        func chained(_ a: Int, _ b: Int) -> Bool {
            pairs[b].saved == pairs[a].saved + 1 && pairs[b].read == pairs[a].read + 1
        }
        for k in pairs.indices.dropFirst() where !keep[k] && keep[k - 1] && chained(k - 1, k) { keep[k] = true }
        for k in pairs.indices.dropLast().reversed() where !keep[k] && keep[k + 1] && chained(k, k + 1) { keep[k] = true }
        return pairs.indices.filter { keep[$0] }.map { pairs[$0] }
    }

    /// The saved chat with the new read fitted in, and where the read landed.
    /// Where both have a message, the longer text and the saved speaker (which
    /// may have been fixed by hand) win. Between and after shared messages the
    /// new screenshot is the latest word, except that saved messages after the
    /// read are kept when the read is an older part of the chat (scrolled up).
    static func join(_ saved: [ChatMessage], _ read: [ChatMessage]) -> (messages: [ChatMessage], latest: Range<Int>) {
        let pairs = matches(saved, read)
        guard let first = pairs.first, let last = pairs.last else {
            return (saved + read, saved.count..<(saved.count + read.count))
        }
        var out = Array(saved[..<first.saved])
        // Read messages before the first shared one: new only if nothing saved comes before.
        let lead = first.saved == 0 ? Array(read[..<first.read]) : []
        let start = out.count
        out += lead
        for (k, pair) in pairs.enumerated() {
            var message = saved[pair.saved]
            let fresh = read[pair.read]
            if Transcript.normalized(fresh.text).count > Transcript.normalized(message.text).count {
                message.text = fresh.text
            }
            if message.replyTo == nil { message.replyTo = fresh.replyTo }
            out.append(message)
            if k + 1 < pairs.count {
                let next = pairs[k + 1]
                let savedGap = next.saved - pair.saved - 1, readGap = next.read - pair.read - 1
                // The new screenshot wins in between, unless the saved chat has
                // far more there (then the match is a repeat, not an overlap).
                out += savedGap > readGap + 3 ? saved[(pair.saved + 1)..<next.saved]
                                              : read[(pair.read + 1)..<next.read]
            }
        }
        let readTail = read[(last.read + 1)...]
        out += readTail
        let end = out.count
        if readTail.isEmpty {
            out += saved[(last.saved + 1)...]   // the read was an older part of the chat
        }
        return (out, start..<end)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
