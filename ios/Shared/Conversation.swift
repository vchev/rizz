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

    enum CodingKeys: String, CodingKey {
        case text
    }
}

enum Transcript {
    /// Joins messages read from several screenshots of the same thread, in order.
    /// Screenshots usually overlap, so the longest run of messages that ends the
    /// earlier part and starts the later part is kept only once.
    static func append(_ next: [ChatMessage], to earlier: [ChatMessage]) -> [ChatMessage] {
        earlier + next.dropFirst(overlap(earlier, then: next))
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
        return ordered.reduce([]) { append($1, to: $0) }
    }

    static func joinBestOrder(_ first: [ChatMessage], _ second: [ChatMessage]) -> [ChatMessage] {
        joinBestOrder([first, second])
    }

    /// How many messages at the end of `earlier` repeat at the start of `next`.
    static func overlap(_ earlier: [ChatMessage], then next: [ChatMessage]) -> Int {
        let maxOverlap = min(earlier.count, next.count)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if zip(earlier.suffix(size), next.prefix(size)).allSatisfy({ same($0, $1) }) {
                return size
            }
        }
        return 0
    }

    private static func same(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        a.speaker == b.speaker && normalized(a.text) == normalized(b.text)
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
