import Foundation

/// Who sent a message. Matches the speakers the reply engine uses:
/// right-aligned bubble = "you", left-aligned bubble = "them".
enum Speaker: String, Codable, Hashable {
    case you
    case them

    var flipped: Speaker { self == .you ? .them : .you }
}

/// One chat bubble read from a screenshot.
struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var speaker: Speaker
    var text: String
    /// For a quoted reply: the start of the earlier message it quotes, as the
    /// app shows it ("Maybe. Not necessary. Sometimes it's j…").
    var replyTo: String? = nil

    enum CodingKeys: String, CodingKey {
        case speaker, text
        case replyTo = "reply_to"
    }
}

extension ChatMessage {
    /// A made-up chat for trying the app without a screenshot. Never used to learn the user's voice.
    static let example: [ChatMessage] = [
        ChatMessage(speaker: .them, text: "ok your third photo, is that a pottery wheel??"),
        ChatMessage(speaker: .you, text: "guilty. I took one class and now I think I'm a ceramicist"),
        ChatMessage(speaker: .them, text: "haha that's amazing. what did you make"),
        ChatMessage(speaker: .you, text: "a bowl that is technically also a plate"),
        ChatMessage(speaker: .them, text: "honestly iconic. are you free this weekend? I want to see this bowl-plate"),
    ]
}

/// One suggested reply.
struct ReplySuggestion: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    /// A short tag for the reply's angle ("playful", "direct"), when the engine sends one.
    var label: String? = nil

    enum CodingKeys: String, CodingKey {
        case text, label
    }
}

enum Transcript {
    /// Joins messages read from several screenshots of the same thread, in order.
    /// Screenshots usually overlap, so the longest run of messages that ends the
    /// earlier part and starts the later part is kept only once. Where the two
    /// copies differ (a bubble cut off at the screen edge, a letter misread),
    /// the longer copy is kept.
    static func append(_ next: [ChatMessage], to earlier: [ChatMessage]) -> [ChatMessage] {
        merge(earlier, then: next, overlapping: overlap(earlier, then: next))
    }

    /// Joins screenshots' messages in whichever order they overlap best.
    /// `parts` is in the order the screenshots were taken. People scroll both
    /// ways between screenshots, so the reverse order is tried too. With no
    /// overlap either way, the order they were taken wins.
    /// Moves screenshot `from` to position `to` and joins the chat again in that
    /// order. A message the person switched to the other speaker (found in
    /// `current` by its text) keeps the speaker they chose.
    static func reorder(_ parts: [[ChatMessage]], from: Int, to: Int,
                        keepingSpeakersOf current: [ChatMessage]) -> (parts: [[ChatMessage]], joined: [ChatMessage]) {
        guard parts.indices.contains(from), parts.indices.contains(to) else {
            return (parts, parts.reduce([ChatMessage]()) { append($1, to: $0) })
        }
        var chosen: [String: Speaker] = [:]
        for message in current { chosen[normalized(message.text)] = message.speaker }
        var moved = parts.map { part in
            part.map { message -> ChatMessage in
                var m = message
                if let speaker = chosen[normalized(m.text)] { m.speaker = speaker }
                return m
            }
        }
        moved.insert(moved.remove(at: from), at: to)
        return (moved, moved.reduce([ChatMessage]()) { append($1, to: $0) })
    }

    /// What one screenshot tells us about its place in the chat.
    struct Clues {
        var first: Date?
        var last: Date?
        var hasReceipt = false
    }

    /// Puts screenshots in chat order, whatever order they were taken in (people
    /// often screenshot the bottom first, then scroll up). Tried in this order:
    /// messages repeated across screenshots, then the chat's own timestamps, then
    /// the "Delivered"/"Read" note under the newest message. With no clue at all,
    /// the order they were taken in stands. Returns indexes into `parts`.
    static func chatOrder(_ parts: [[ChatMessage]], clues: [Clues]) -> [Int] {
        let n = parts.count
        guard n > 1, n <= 4, clues.count == n else { return Array(0..<n) }
        func permutations(_ items: [Int]) -> [[Int]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[Int]] in
                var rest = items
                let head = rest.remove(at: i)
                return permutations(rest).map { [head] + $0 }
            }
        }
        func score(_ order: [Int]) -> (Int, Int, Int) {
            let overlaps = zip(order, order.dropFirst()).reduce(0) { $0 + overlap(parts[$1.0], then: parts[$1.1]) }
            var times = 0
            for a in 0..<order.count {
                for b in (a + 1)..<order.count {
                    let early = clues[order[a]], late = clues[order[b]]
                    guard let earlyLast = early.last, let earlyFirst = early.first,
                          let lateFirst = late.first, let lateLast = late.last else { continue }
                    if earlyLast <= lateFirst && earlyFirst < lateLast { times += 1 }
                    if earlyFirst > lateLast { times -= 1 }
                }
            }
            let receipt = clues[order.last!].hasReceipt ? 1 : (order.dropLast().contains { clues[$0].hasReceipt } ? -1 : 0)
            return (overlaps, times, receipt)
        }
        var best = Array(0..<n)
        var bestScore = score(best)
        for order in permutations(Array(0..<n)) {
            let s = score(order)
            if s > bestScore { best = order; bestScore = s }
        }
        return best
    }

    /// Reads a chat timestamp ("today 9:41 pm", "yesterday 21:05", "tue 9:41 pm",
    /// "tue, nov 3 at 9:41 pm", "9:41 pm") as a date, given when the screenshot was taken.
    static func stampDate(_ raw: String, taken: Date, calendar: Calendar = .current) -> Date? {
        let text = raw.lowercased()
        guard let time = text.range(of: #"(\d{1,2}):(\d{2})\s*(am|pm)?$"#, options: .regularExpression) else { return nil }
        let clock = String(text[time])
        let digits = clock.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count >= 2, var hour = digits.first, digits[1] < 60 else { return nil }
        if clock.hasSuffix("pm") && hour < 12 { hour += 12 }
        if clock.hasSuffix("am") && hour == 12 { hour = 0 }
        guard hour < 24 else { return nil }
        let head = String(text[..<time.lowerBound])
        let today = calendar.startOfDay(for: taken)
        var day = today
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let words = head.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if let m = words.firstIndex(where: { w in months.contains { w.hasPrefix($0) } }),
           let month = months.firstIndex(where: { words[m].hasPrefix($0) }),
           m + 1 < words.count, let dayNumber = Int(words[m + 1]) {
            var parts = calendar.dateComponents([.year], from: today)
            if m + 2 < words.count, let year = Int(words[m + 2]), year > 1900 { parts.year = year }
            parts.month = month + 1
            parts.day = dayNumber
            guard var date = calendar.date(from: parts) else { return nil }
            if date > today, let lastYear = calendar.date(byAdding: .year, value: -1, to: date) { date = lastYear }
            day = date
        } else if words.contains("yesterday") {
            day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        } else if let w = words.first(where: { w in weekdays.contains { w.hasPrefix($0) } }),
                  let weekday = weekdays.firstIndex(where: { w.hasPrefix($0) }) {
            // A weekday name means within the last week, before today.
            let todayWeekday = calendar.component(.weekday, from: today) - 1
            var back = (todayWeekday - weekday + 7) % 7
            if back == 0 { back = 7 }
            day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
        }
        return calendar.date(bySettingHour: hour, minute: digits[1], second: 0, of: day)
    }

    static func joinBestOrder(_ parts: [[ChatMessage]]) -> [ChatMessage] {
        func totalOverlap(_ ordered: [[ChatMessage]]) -> Int {
            zip(ordered, ordered.dropFirst()).reduce(0) { $0 + overlap($1.0, then: $1.1) }
        }
        let ordered = totalOverlap(parts.reversed()) > totalOverlap(parts) ? Array(parts.reversed()) : parts
        return ordered.reduce([ChatMessage]()) { append($1, to: $0) }
    }

    /// Which screenshots (indexes, oldest first) belong to the same chat as the
    /// newest one. An older screenshot is kept if it shares a message with the
    /// kept ones, or was taken within 2 minutes of the next one (scrolling a
    /// whole screen between shots). Otherwise it's from another chat or an
    /// older moment, and mixing it in would muddle the replies.
    static func sameChat(_ parts: [[ChatMessage]], taken: [Date], window: TimeInterval = 120) -> [Int] {
        guard let newest = parts.indices.last else { return [] }
        var kept = [newest]
        var joined = parts[newest]
        for i in stride(from: newest - 1, through: 0, by: -1) {
            let shares = overlap(parts[i], then: joined) > 0 || overlap(joined, then: parts[i]) > 0
                || parts[i].contains { m in joined.contains { similar($0.text, m.text) && normalized(m.text).count >= 8 } }
            let close = i + 1 < taken.count && abs(taken[i + 1].timeIntervalSince(taken[i])) <= window
            guard shares || close else { break }
            kept.insert(i, at: 0)
            joined = parts[i] + joined
        }
        return kept
    }

    static func joinBestOrder(_ first: [ChatMessage], _ second: [ChatMessage]) -> [ChatMessage] {
        joinBestOrder([first, second])
    }

    /// How many messages at the end of `earlier` repeat at the start of `next`.
    /// The first repeated message may be cut off at the top of `next` (only its
    /// end shows) and the last one cut off at the bottom of `earlier` (only its
    /// start shows). `matchSpeaker: false` compares text only, for chats where
    /// someone fixed a speaker by hand.
    static func overlap(_ earlier: [ChatMessage], then next: [ChatMessage], matchSpeaker: Bool = true) -> Int {
        let maxOverlap = min(earlier.count, next.count)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            let a = Array(earlier.suffix(size)), b = Array(next.prefix(size))
            let fits = (0..<size).allSatisfy { i in
                if matchSpeaker && a[i].speaker != b[i].speaker { return false }
                if similar(a[i].text, b[i].text) { return true }
                if i == 0 && isCutOff(b[i].text, of: a[i].text, keepingEnd: true) { return true }
                if i == size - 1 && isCutOff(a[i].text, of: b[i].text, keepingEnd: false) { return true }
                return false
            }
            if fits { return size }
        }
        return 0
    }

    enum Side { case earlier, next }

    /// `earlier` followed by `next`, with `count` overlapping messages kept once.
    /// Each overlapping message keeps the longer text; its speaker comes from
    /// `speakersFrom`, or from the longer copy when that's nil.
    static func merge(_ earlier: [ChatMessage], then next: [ChatMessage], overlapping count: Int,
                      speakersFrom: Side? = nil) -> [ChatMessage] {
        var out = earlier
        let start = earlier.count - count
        for i in 0..<count {
            let nextIsLonger = normalized(next[i].text).count > normalized(out[start + i].text).count
            if nextIsLonger { out[start + i].text = next[i].text }
            if out[start + i].replyTo == nil { out[start + i].replyTo = next[i].replyTo }
            switch speakersFrom {
            case .earlier: break
            case .next: out[start + i].speaker = next[i].speaker
            case nil: if nextIsLonger { out[start + i].speaker = next[i].speaker }
            }
        }
        return out + next.dropFirst(count)
    }

    /// Whether `part` sits inside `saved` as a run of messages (a screenshot of
    /// part of a chat that's already known).
    static func contains(_ saved: [ChatMessage], _ part: [ChatMessage]) -> Bool {
        guard !part.isEmpty, part.count <= saved.count else { return false }
        for start in 0...(saved.count - part.count) {
            if (0..<part.count).allSatisfy({ similar(saved[start + $0].text, part[$0].text) }) { return true }
        }
        return false
    }

    /// Same text, allowing for small text-recognition differences
    /// (punctuation, case, a letter or two in a longer message).
    static func similar(_ a: String, _ b: String) -> Bool {
        let x = normalized(a), y = normalized(b)
        if x == y { return true }
        // Times, dates and numbers must match exactly ("at 7" isn't "at 8").
        guard x.filter(\.isNumber) == y.filter(\.isNumber) else { return false }
        let longest = max(x.count, y.count)
        guard longest >= 12 else { return false }
        let allowed = longest / 10   // up to 10% of the letters may differ
        return editDistance(x, y, limit: allowed) <= allowed
    }

    /// A bubble cut off at the screen edge: `part` is the end (`keepingEnd`) or
    /// the start of `whole`, and long enough not to match by chance.
    static func isCutOff(_ part: String, of whole: String, keepingEnd: Bool) -> Bool {
        let p = normalized(part), w = normalized(whole)
        guard p.count >= 10, p.count < w.count else { return false }
        return keepingEnd ? w.hasSuffix(p) : w.hasPrefix(p)
    }

    static func normalized(_ s: String) -> String {
        let cleaned = String(s.lowercased().map { (c: Character) -> Character in
            c.isLetter || c.isNumber ? c : " "
        })
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// Levenshtein distance, giving up (returning limit + 1) once it's over `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if row.min()! > limit { return limit + 1 }
            prev = row
        }
        return prev[b.count]
    }
}
