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

    enum CodingKeys: String, CodingKey {
        case speaker, text
    }
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
    static func joinBestOrder(_ parts: [[ChatMessage]]) -> [ChatMessage] {
        func totalOverlap(_ ordered: [[ChatMessage]]) -> Int {
            zip(ordered, ordered.dropFirst()).reduce(0) { $0 + overlap($1.0, then: $1.1) }
        }
        let ordered = totalOverlap(parts.reversed()) > totalOverlap(parts) ? Array(parts.reversed()) : parts
        return ordered.reduce([ChatMessage]()) { append($1, to: $0) }
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
