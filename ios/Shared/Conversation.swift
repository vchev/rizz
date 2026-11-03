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
        let maxOverlap = min(earlier.count, next.count)
        var overlap = 0
        if maxOverlap > 0 {
            for size in stride(from: maxOverlap, through: 1, by: -1) {
                let tail = earlier.suffix(size)
                let head = next.prefix(size)
                if zip(tail, head).allSatisfy({ same($0, $1) }) {
                    overlap = size
                    break
                }
            }
        }
        return earlier + next.dropFirst(overlap)
    }

    private static func same(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        a.speaker == b.speaker && normalized(a.text) == normalized(b.text)
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
