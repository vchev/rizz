import CoreGraphics
import Foundation

/// One line of text found in a screenshot.
/// `box` is in normalized coordinates (0...1) with the origin at the TOP-left.
struct TextLine: Hashable {
    var text: String
    var box: CGRect
}

/// Turns lines of text from a chat screenshot into messages.
///
/// Speakers come from alignment only (same rule as the test-case tools):
/// right-aligned bubble = "you", left-aligned = "them", centered text
/// (timestamps, "Delivered", the contact's name) is dropped.
enum BubbleLayout {
    /// The top of a screenshot is the status bar and the contact header.
    static let topCutoff: CGFloat = 0.07
    /// Text whose left and right margins differ by less than this is "centered".
    static let centerTolerance: CGFloat = 0.06
    /// Centered text must also sit at least this far from the left edge.
    static let centerMinMargin: CGFloat = 0.12
    /// Lines whose left edges differ by less than this can share a bubble.
    static let sameEdgeTolerance: CGFloat = 0.03
    /// Max vertical gap between two lines of one bubble, as a share of line height.
    static let lineGapFactor: CGFloat = 0.8

    static func messages(from lines: [TextLine]) -> [ChatMessage] {
        let kept = lines
            .filter { $0.box.minY >= topCutoff }
            .filter { !isChrome($0.text) }
            .sorted { $0.box.minY < $1.box.minY }

        return groupIntoBubbles(kept).compactMap { bubble in
            guard let speaker = speaker(for: bubble.box) else { return nil }
            let text = bubble.lines.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ChatMessage(speaker: speaker, text: text)
        }
    }

    /// nil means centered text, which is dropped.
    static func speaker(for box: CGRect) -> Speaker? {
        let leftMargin = box.minX
        let rightMargin = 1 - box.maxX
        if abs(leftMargin - rightMargin) < centerTolerance && leftMargin > centerMinMargin {
            return nil
        }
        return leftMargin < rightMargin ? .them : .you
    }

    struct Bubble {
        var lines: [TextLine]
        var box: CGRect
    }

    /// Lines of a wrapped bubble are stacked tightly and share a left edge
    /// (text is left-aligned inside both kinds of bubble).
    static func groupIntoBubbles(_ lines: [TextLine]) -> [Bubble] {
        var bubbles: [Bubble] = []
        for line in lines {
            if var last = bubbles.last, let prev = last.lines.last,
               abs(line.box.minX - prev.box.minX) < sameEdgeTolerance,
               line.box.minY - prev.box.maxY < prev.box.height * lineGapFactor {
                last.lines.append(line)
                last.box = last.box.union(line.box)
                bubbles[bubbles.count - 1] = last
            } else {
                bubbles.append(Bubble(lines: [line], box: line.box))
            }
        }
        return bubbles
    }

    /// App furniture that is not part of the conversation.
    static func isChrome(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        let lower = text.lowercased()
        let exact: Set<String> = [
            "imessage", "text message", "message", "messages", "delivered", "read", "seen",
            "type a message", "send a message", "write a message", "today", "yesterday",
        ]
        if exact.contains(lower) { return true }
        for prefix in ["read ", "seen ", "delivered "] where lower.hasPrefix(prefix) {
            if looksLikeTime(String(lower.dropFirst(prefix.count))) { return true }
        }
        return looksLikeTime(lower)
    }

    /// "9:41", "9:41 PM", "Today 9:41 PM", "Tue, Nov 3 at 9:41 PM" and similar.
    static func looksLikeTime(_ lower: String) -> Bool {
        let pattern = #"^((today|yesterday|mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s*)?([a-z]{3,9}\.?\s+\d{1,2},?\s*(\d{4})?\s*)?(at\s+)?\d{1,2}:\d{2}\s*(am|pm)?$"#
        return lower.range(of: pattern, options: .regularExpression) != nil
    }
}
