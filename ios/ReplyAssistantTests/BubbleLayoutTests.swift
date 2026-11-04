import CoreGraphics
import XCTest

final class BubbleLayoutTests: XCTestCase {
    private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 0.02) -> TextLine {
        TextLine(text: text, box: CGRect(x: x, y: y, width: w, height: h))
    }

    func testAlignmentDecidesSpeaker() {
        let messages = BubbleLayout.messages(from: [
            line("hey! how was the hike", x: 0.08, y: 0.30, w: 0.45),
            line("so good, my legs are dead", x: 0.45, y: 0.36, w: 0.47),
        ])
        XCTAssertEqual(messages.map(\.speaker), [.them, .you])
        XCTAssertEqual(messages.map(\.text), ["hey! how was the hike", "so good, my legs are dead"])
    }

    func testCenteredTimestampsAndHeaderAreDropped() {
        let messages = BubbleLayout.messages(from: [
            line("9:41", x: 0.06, y: 0.01, w: 0.08),               // status bar
            line("Brad", x: 0.45, y: 0.10, w: 0.10),               // contact name, centered
            line("Today 9:41 PM", x: 0.38, y: 0.20, w: 0.24),      // centered timestamp
            line("you up?", x: 0.08, y: 0.25, w: 0.18),
            line("Delivered", x: 0.80, y: 0.31, w: 0.12),
            line("iMessage", x: 0.12, y: 0.92, w: 0.15),           // input placeholder
        ])
        XCTAssertEqual(messages.map(\.text), ["you up?"])
        XCTAssertEqual(messages.first?.speaker, .them)
    }

    func testWrappedBubbleStaysOneMessageWithTheRightSpeaker() {
        // A right-hand bubble whose last line is short: on its own it would look left-aligned.
        let messages = BubbleLayout.messages(from: [
            line("ok so I tried that ramen place you", x: 0.30, y: 0.40, w: 0.62),
            line("mentioned and it was amazing", x: 0.30, y: 0.425, w: 0.55),
            line("thank you", x: 0.30, y: 0.45, w: 0.18),
            line("told you!!", x: 0.08, y: 0.50, w: 0.20),
        ])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].speaker, .you)
        XCTAssertEqual(messages[0].text, "ok so I tried that ramen place you mentioned and it was amazing thank you")
        XCTAssertEqual(messages[1].speaker, .them)
    }

    func testOrderFollowsPositionNotInputOrder() {
        let messages = BubbleLayout.messages(from: [
            line("second", x: 0.70, y: 0.60, w: 0.20),
            line("first", x: 0.08, y: 0.20, w: 0.20),
        ])
        XCTAssertEqual(messages.map(\.text), ["first", "second"])
    }

    func testMessagesThatMentionSeenOrReadAreKept() {
        XCTAssertFalse(BubbleLayout.isChrome("Seen that movie yet?"))
        XCTAssertFalse(BubbleLayout.isChrome("Read any good books lately"))
        XCTAssertTrue(BubbleLayout.isChrome("Read 9:41 PM"))
        XCTAssertTrue(BubbleLayout.isChrome("Tue, Nov 3 at 9:41 PM"))
    }

    func testOverlappingScreenshotsAreJoinedWithoutRepeats() {
        let a = [ChatMessage(speaker: .them, text: "hi"), ChatMessage(speaker: .you, text: "hey you"),
                 ChatMessage(speaker: .them, text: "dinner fri?")]
        let b = [ChatMessage(speaker: .you, text: "hey  you"), ChatMessage(speaker: .them, text: "Dinner fri?"),
                 ChatMessage(speaker: .you, text: "yes!")]
        XCTAssertEqual(Transcript.append(b, to: a).map(\.text), ["hi", "hey you", "dinner fri?", "yes!"])
        XCTAssertEqual(Transcript.append(b, to: []).count, 3)
    }

    func testRequestJSONMatchesTheBackendContract() throws {
        let data = try JSONEncoder().encode([ChatMessage(speaker: .them, text: "hi")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(json, [["speaker": "them", "text": "hi"]])
    }
}

final class TranscriptOrderTests: XCTestCase {
    private func msgs(_ pairs: [(Speaker, String)]) -> [ChatMessage] {
        pairs.map { ChatMessage(speaker: $0.0, text: $0.1) }
    }

    func testScrollingUpBetweenScreenshotsStillGivesChatOrder() {
        let newer = msgs([(.them, "dinner fri?"), (.you, "yes!"), (.them, "7pm?")])
        let older = msgs([(.them, "hi"), (.you, "hey you"), (.them, "dinner fri?")])
        // Taken in this order: newer part of the chat first, then scrolled up.
        XCTAssertEqual(Transcript.joinBestOrder(newer, older).map(\.text),
                       ["hi", "hey you", "dinner fri?", "yes!", "7pm?"])
    }

    func testNoOverlapKeepsTheOrderTheyWereTaken() {
        let a = msgs([(.them, "one")])
        let b = msgs([(.you, "two")])
        XCTAssertEqual(Transcript.joinBestOrder(a, b).map(\.text), ["one", "two"])
    }
}

final class ThreeScreenshotTests: XCTestCase {
    func testThreeScreenshotsTakenNewestFirstAreJoinedInChatOrder() {
        func m(_ s: Speaker, _ t: String) -> ChatMessage { ChatMessage(speaker: s, text: t) }
        let latest = [m(.them, "c"), m(.you, "d"), m(.them, "e")]
        let middle = [m(.you, "b"), m(.them, "c")]
        let oldest = [m(.them, "a"), m(.you, "b")]
        XCTAssertEqual(Transcript.joinBestOrder([latest, middle, oldest]).map(\.text), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(Transcript.joinBestOrder([oldest, middle, latest]).map(\.text), ["a", "b", "c", "d", "e"])
    }
}

final class ReplySuggestionDecodingTests: XCTestCase {
    func testLabelIsOptional() throws {
        let json = #"[{"text": "dangerously confident tbh", "label": "playful"}, {"text": "coffee?"}]"#
        let replies = try JSONDecoder().decode([ReplySuggestion].self, from: Data(json.utf8))
        XCTAssertEqual(replies.map(\.text), ["dangerously confident tbh", "coffee?"])
        XCTAssertEqual(replies.map(\.label), ["playful", nil])
    }
}
