import CoreGraphics
import Foundation

/// One line of text found in a screenshot.
/// `box` is in normalized coordinates (0...1) with the origin at the TOP-left.
struct TextLine: Hashable {
    var text: String
    var box: CGRect
    /// How sure text recognition was (0...1). Low = likely misread.
    var confidence: Float = 1
    /// Whether the text sits on a bubble (a colour different from the screen
    /// background). nil = not measured.
    var onBubble: Bool? = nil
    /// Greyed-out text, like a placeholder ("Aa", "Type a message").
    var isFaint: Bool = false
    /// Left and right edges of the bubble around the text, when measured.
    var bubbleMinX: CGFloat? = nil
    var bubbleMaxX: CGFloat? = nil
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
    /// Lines read with less confidence than this are dropped as gibberish.
    static let minConfidence: Float = 0.4

    static func messages(from lines: [TextLine]) -> [ChatMessage] {
        let kept = aboveTextBox(lines)
            .filter { $0.box.minY >= topCutoff }
            .filter { !isChrome($0.text) }
            .filter { $0.confidence >= minConfidence }
            .filter { $0.text.contains(where: { $0.isLetter || $0.isNumber }) }
            .filter { $0.onBubble != false && !$0.isFaint }
            .sorted { $0.box.minY < $1.box.minY }

        // A quote indented inside its bubble can end up as a group of its own:
        // it then belongs to the message right below it.
        var pendingQuote: String?
        return groupIntoBubbles(dropTinyText(kept)).compactMap { bubble in
            guard let speaker = speaker(for: bubble) else { return nil }
            let (lines, quote) = splitQuote(bubble.lines)
            guard !lines.isEmpty else {
                pendingQuote = quote ?? pendingQuote
                return nil
            }
            let text = lines.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let replyTo = quote ?? pendingQuote
            pendingQuote = nil
            return text.isEmpty ? nil : ChatMessage(speaker: speaker, text: text, replyTo: replyTo)
        }
    }

    /// Drops the text box and any keyboard below it. A screenshot taken while
    /// typing shows the keyboard (Apple's or Coax's), and its keys ("space",
    /// "return", "123", rows of letters) are not messages.
    static func aboveTextBox(_ lines: [TextLine]) -> [TextLine] {
        guard let cut = textBoxTop(lines) else { return lines }
        return lines.filter { $0.box.minY < cut }
    }

    /// Where the text box (and everything under it) starts, or nil when the
    /// screenshot shows no keyboard and no text-box placeholder.
    static func textBoxTop(_ lines: [TextLine]) -> CGFloat? {
        var cuts: [CGFloat] = []
        // The placeholder in an empty text box ("iMessage", "Aa", "Send a message").
        let placeholders: Set<String> = [
            "imessage", "text message", "rcs message", "message", "type a message", "send a message",
            "write a message", "aa", "start typing", "type something", "say something nice",
        ]
        if let box = lines.last(where: {
            $0.box.minY > 0.4 && placeholders.contains($0.text.trimmingCharacters(in: .whitespaces).lowercased())
        }) {
            cuts.append(box.box.minY - box.box.height * 0.5)
        }
        // Coax's own bar ("Last screenshot", "Last 2") sits just under the text box.
        if let bar = lines.first(where: { $0.box.minY > 0.4 && isCoaxBar($0.text) }) {
            cuts.append(bar.box.minY - textBoxHeight)
        }
        // A keyboard's bottom row: "123", "space", "return". Two of them are
        // needed, so a message that just says "space" stays.
        let bottomRow = lines.filter { $0.box.minY > 0.7 && isBottomRowKey($0.text) }
        if bottomRow.count >= 2, let row = bottomRow.map(\.box.minY).min() {
            cuts.append(row - keyboardHeight)
        }
        return cuts.min()
    }

    /// From the top of the text box down to the keyboard's bottom row: three
    /// rows of letters, the suggestion bar and the text box.
    static let keyboardHeight: CGFloat = 0.30
    /// The text box above the keyboard, with its margins.
    static let textBoxHeight: CGFloat = 0.07

    static func isBottomRowKey(_ raw: String) -> Bool {
        let keys: Set<String> = ["space", "return", "123", "abc", "#+=", "go", "search", "done", "next",
                                 "join", "emoji"]
        return keys.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Words only Coax's own screens show. A screenshot of the Coax app or keyboard
    /// (say, taken to send feedback) is not a chat and must not be read as one.
    static let coaxScreenPhrases = [
        "here's the move", "get replies from a screenshot", "screenshot the chat", "coax does the rest",
        "tap a message to switch who sent it", "get new replies", "scan the last", "scan again",
        "tap one to put it in the message box", "tap another reply to swap it in", "ready for your next screenshot",
        "wrong chat? start fresh", "start using coax", "add the coax keyboard", "know what to text back",
        "recent chats", "or paste text you copied", "what i read", "see all replies", "tap a reply to copy it",
        "your latest screenshot", "make it sound like you", "waiting for a screenshot", "writing replies",
        "try it with an example chat", "free to start", "settings › coax", "allow full access",
    ]
    static let moodTags: Set<String> = ["funny", "flirty", "sweet", "chill", "bold", "shorter"]

    /// Two or more Coax-only phrases (the row of mood tags counts as one) means a
    /// screenshot of Coax. One alone could be a message that happens to say it.
    static func isCoaxScreen(_ lines: [TextLine]) -> Bool {
        let texts = lines.map { $0.text.lowercased().replacingOccurrences(of: "’", with: "'") }
        var hits = Set(coaxScreenPhrases.filter { phrase in texts.contains { $0.contains(phrase) } })
        let moods = Set(texts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { moodTags.contains($0) })
        if moods.count >= 3 { hits.insert("mood tags") }
        return hits.count >= 2
    }

    static func isCoaxBar(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces)
        return ["Last screenshot", "Last 2", "Last 3"].contains(text)
    }

    /// Text much smaller than the chat's own is inside a picture someone sent
    /// (often a screenshot of another chat), not a message in this one.
    static let tinyTextFactor: CGFloat = 0.55

    static func dropTinyText(_ lines: [TextLine]) -> [TextLine] {
        let heights = lines.map(\.box.height).sorted()
        guard heights.count >= 3 else { return lines }
        let median = heights[heights.count / 2]
        return lines.filter { $0.box.height >= median * tinyTextFactor }
    }

    /// A quoted reply (Bumble, WhatsApp, Instagram) shows the quoted person's
    /// name, then a shortened copy of their message ending in "…", above the
    /// actual reply. Those lines aren't part of the message (the name would
    /// muddle who's who); the quote is kept aside, so replies know which
    /// earlier message this one answered.
    static func splitQuote(_ lines: [TextLine]) -> (lines: [TextLine], quote: String?) {
        var out: [TextLine] = []
        var quote: String?
        var i = 0
        while i < lines.count {
            if i + 1 < lines.count, isNameLike(lines[i].text), isShortened(lines[i + 1].text) {
                quote = quote ?? lines[i + 1].text.trimmingCharacters(in: .whitespaces)
                i += 2
                continue
            }
            out.append(lines[i])
            i += 1
        }
        return (out, quote)
    }

    static func withoutQuotes(_ lines: [TextLine]) -> [TextLine] { splitQuote(lines).lines }

    /// The "replying to" bar some apps show above the text box when you've
    /// started a quoted reply (Bumble: "Chai" / "Btw! I'm sure you get this…").
    /// It sits off the bubbles, below the last message. Returns the quoted text.
    static func replyingTo(in lines: [TextLine]) -> String? {
        let sorted = aboveTextBox(lines).filter { $0.confidence >= minConfidence }.sorted { $0.box.minY < $1.box.minY }
        let lastBubbleBottom = sorted.filter { $0.onBubble == true }.map(\.box.maxY).max() ?? 0
        for (name, quote) in zip(sorted, sorted.dropFirst()) {
            guard name.onBubble != true, quote.onBubble != true,
                  name.box.minY > lastBubbleBottom, name.box.minY > 0.5,
                  abs(name.box.minX - quote.box.minX) < sameEdgeTolerance,
                  isNameLike(name.text), isShortened(quote.text) else { continue }
            return quote.text.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "Chai", "Vanessa", "Mary Jo": one or two capitalized words, no punctuation.
    static func isNameLike(_ raw: String) -> Bool {
        let words = raw.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard (1...2).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase, word.count <= 15 else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
        }
    }

    static func isShortened(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces)
        return text.hasSuffix("…") || text.hasSuffix("...")
    }

    /// Your bubbles touch the right margin; theirs don't (they may sit after a
    /// profile photo, so their left edge can be as far in as yours).
    static let rightMarginForYou: CGFloat = 0.06
    /// Chat bubbles stop short of the screen's width; wider boxes are cards
    /// quoting a profile (Hinge prompts and photos) or link previews.
    static let maxBubbleWidth: CGFloat = 0.88

    /// Uses the bubble's own edges when they were measured, else the text's.
    static func speaker(for bubble: Bubble) -> Speaker? {
        let mins = bubble.lines.compactMap(\.bubbleMinX)
        let maxes = bubble.lines.compactMap(\.bubbleMaxX)
        guard let minX = mins.min(), let maxX = maxes.max() else { return speaker(for: bubble.box) }
        let left = minX, right = 1 - maxX
        if abs(left - right) < 0.03 && left > 0.25 { return nil }   // a centered pill (date, notice)
        if maxX - minX > maxBubbleWidth { return nil }   // a full-width card (Hinge prompt, link preview)
        return right < rightMarginForYou && left > right ? .you : .them
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
            "aa", "start typing", "type something", "say something nice", "ask them out",
            "your turn", "their turn", "send", "gif",
        ]
        if exact.contains(lower) { return true }
        for prefix in ["read ", "seen ", "delivered "] where lower.hasPrefix(prefix) {
            if looksLikeTime(String(lower.dropFirst(prefix.count))) { return true }
        }
        return looksLikeTime(lower)
    }

    /// Clues to where a screenshot sits in the chat: its timestamps ("Today 9:41 PM",
    /// top to bottom) and whether it shows a "Delivered" / "Read" / "Seen" note, which
    /// only appears under the newest message.
    static func timeClues(_ lines: [TextLine]) -> (stamps: [String], receipt: Bool) {
        let shown = aboveTextBox(lines)
            .filter { $0.box.minY >= topCutoff }
            .sorted { $0.box.minY < $1.box.minY }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var stamps: [String] = []
        var receipt = false
        for text in shown {
            if ["delivered", "read", "seen"].contains(text) { receipt = true; continue }
            if let prefix = ["read ", "seen ", "delivered "].first(where: { text.hasPrefix($0) }),
               looksLikeTime(String(text.dropFirst(prefix.count))) {
                receipt = true
                continue
            }
            if looksLikeTime(text) { stamps.append(text) }
        }
        return (stamps, receipt)
    }

    /// "9:41", "9:41 PM", "Today 9:41 PM", "Tue, Nov 3 at 9:41 PM" and similar.
    static func looksLikeTime(_ lower: String) -> Bool {
        let pattern = #"^((today|yesterday|mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s*)?([a-z]{3,9}\.?\s+\d{1,2},?\s*(\d{4})?\s*)?(at\s+)?\d{1,2}:\d{2}\s*(am|pm)?$"#
        return lower.range(of: pattern, options: .regularExpression) != nil
    }
}
