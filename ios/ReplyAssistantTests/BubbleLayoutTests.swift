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

    /// Bumble quoted replies: the quoted name and the shortened quote are not
    /// messages (Vanessa's Nov 4 Bumble screenshot with Chai).
    func testQuotedRepliesAreDropped() {
        let messages = BubbleLayout.messages(from: [
            line("Vanessa", x: 0.09, y: 0.50, w: 0.12, h: 0.013),
            line("So it's dependent on who updates thei...", x: 0.09, y: 0.517, w: 0.55, h: 0.013),
            line("Maybe. Not necessary.", x: 0.06, y: 0.54, w: 0.42),
            line("Sometimes it's just an experiment", x: 0.06, y: 0.565, w: 0.60),
            line("Chai", x: 0.36, y: 0.63, w: 0.06, h: 0.013),
            line("Maybe. Not necessary. Sometimes it's j…", x: 0.36, y: 0.647, w: 0.56, h: 0.013),
            line("Ohh that's true!", x: 0.35, y: 0.665, w: 0.28),
        ])
        XCTAssertEqual(messages.map(\.text), ["Maybe. Not necessary. Sometimes it's just an experiment", "Ohh that's true!"])
        XCTAssertEqual(messages.map(\.speaker), [.them, .you])
        // The quotes are kept aside, so replies know what each one answered.
        XCTAssertEqual(messages.map(\.replyTo), ["So it's dependent on who updates thei...",
                                                 "Maybe. Not necessary. Sometimes it's j…"])
    }

    func testReplyingToBarAboveTheTextBox() {
        var name = line("Chai", x: 0.03, y: 0.535, w: 0.07, h: 0.012)
        var quote = line("Btw! I'm sure you get this a lot but your have a really nic…", x: 0.03, y: 0.552, w: 0.82, h: 0.012)
        var bubble = line("Ohh that's true!", x: 0.35, y: 0.45, w: 0.28)
        name.onBubble = false
        quote.onBubble = false
        bubble.onBubble = true
        XCTAssertEqual(BubbleLayout.replyingTo(in: [bubble, name, quote]),
                       "Btw! I'm sure you get this a lot but your have a really nic…")
        XCTAssertNil(BubbleLayout.replyingTo(in: [bubble]))
    }

    /// A screenshot someone sent inside the chat: its text is tiny and must
    /// not be read as messages (its own "you" bubbles would look like theirs).
    func testTextInsideASharedPictureIsDropped() {
        let messages = BubbleLayout.messages(from: [
            line("Oooh that was my original plan but hasn't", x: 0.10, y: 0.12, w: 0.25, h: 0.007),
            line("the UI changed for you like in the past", x: 0.10, y: 0.128, w: 0.25, h: 0.007),
            line("I haven't updated my app in months", x: 0.05, y: 0.20, w: 0.20, h: 0.007),
            line("Wait it just vanished", x: 0.58, y: 0.32, w: 0.36),
            line("So it's dependent on who", x: 0.47, y: 0.45, w: 0.46),
            line("Btw! I'm sure you get this a lot", x: 0.06, y: 0.68, w: 0.55),
        ])
        XCTAssertEqual(messages.map(\.text), ["Wait it just vanished", "So it's dependent on who", "Btw! I'm sure you get this a lot"])
        XCTAssertEqual(messages.map(\.speaker), [.you, .you, .them])
    }

    /// Vanessa's screenshot (Nov 5) taken with the Coax keyboard open: its
    /// keys were read as messages and crowded out the chat.
    func testCoaxKeyboardInTheScreenshotIsIgnored() {
        let messages = BubbleLayout.messages(from: [
            line("And also, daylight saving", x: 0.08, y: 0.25, w: 0.56, h: 0.025),
            line("ain't it", x: 0.08, y: 0.28, w: 0.15, h: 0.025),
            line("ugh it's the worst", x: 0.56, y: 0.35, w: 0.39, h: 0.025),
            line("Delivered", x: 0.77, y: 0.39, w: 0.16),
            line("iMessage", x: 0.22, y: 0.48, w: 0.21),
            line("Last screenshot", x: 0.28, y: 0.56, w: 0.30),
            line("Q W E R T Y U I O P", x: 0.04, y: 0.64, w: 0.92),
            line("C", x: 0.30, y: 0.76, w: 0.03),
            line("I M", x: 0.05, y: 0.71, w: 0.08),
            line("123", x: 0.04, y: 0.85, w: 0.08),
            line("space", x: 0.40, y: 0.85, w: 0.12),
            line("return", x: 0.82, y: 0.85, w: 0.14),
        ])
        XCTAssertEqual(messages.map(\.text), ["And also, daylight saving ain't it", "ugh it's the worst"])
        XCTAssertEqual(messages.map(\.speaker), [.them, .you])
    }

    /// Apple's keyboard with a typed draft (no placeholder) and suggestions.
    func testAppleKeyboardAndSuggestionsAreIgnored() {
        let messages = BubbleLayout.messages(from: [
            line("are you free saturday?", x: 0.08, y: 0.48, w: 0.45),
            line("I", x: 0.15, y: 0.615, w: 0.02),
            line("Thanks", x: 0.45, y: 0.615, w: 0.12),
            line("I'm", x: 0.80, y: 0.615, w: 0.06),
            line("A S D F G H J K L", x: 0.06, y: 0.74, w: 0.88),
            line("123", x: 0.04, y: 0.87, w: 0.08),
            line("space", x: 0.40, y: 0.87, w: 0.12),
            line("return", x: 0.82, y: 0.87, w: 0.14),
        ])
        XCTAssertEqual(messages.map(\.text), ["are you free saturday?"])
    }

    /// One message saying "space" low on the screen is still a message.
    func testOneKeyWordAloneIsKept() {
        let messages = BubbleLayout.messages(from: [
            line("need some", x: 0.08, y: 0.70, w: 0.20),
            line("space", x: 0.08, y: 0.80, w: 0.12),
        ])
        XCTAssertEqual(messages.count, 2)
    }

    func testScreenshotOfCoaxHomeIsNotAChat() {
        // Vanessa's case: screenshots of Coax's own Home screen read as a "chat".
        XCTAssertTrue(BubbleLayout.isCoaxScreen([
            line("Here’s the move", x: 0.05, y: 0.30, w: 0.40),
            line("Screenshot the chat", x: 0.60, y: 0.40, w: 0.35),
            line("Get replies from a screenshot", x: 0.05, y: 0.60, w: 0.60),
        ]))
        XCTAssertTrue(BubbleLayout.isCoaxScreen([
            line("Funny", x: 0.05, y: 0.80, w: 0.10), line("Flirty", x: 0.20, y: 0.80, w: 0.10),
            line("Sweet", x: 0.35, y: 0.80, w: 0.10), line("Get new replies", x: 0.30, y: 0.88, w: 0.40),
        ]))
    }

    func testChatThatMentionsAScreenshotIsStillAChat() {
        XCTAssertFalse(BubbleLayout.isCoaxScreen([
            line("lol screenshot the chat and send it to me", x: 0.08, y: 0.40, w: 0.60),
            line("you're so funny", x: 0.60, y: 0.50, w: 0.30),
            line("sweet", x: 0.08, y: 0.60, w: 0.10),
        ]))
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

final class ScreenshotTimeOrderTests: XCTestCase {
    private func m(_ s: Speaker, _ t: String) -> ChatMessage { ChatMessage(speaker: s, text: t) }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// Fri Nov 6, 2026, 18:00 UTC.
    private var taken: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 18))! }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testChatTimestampsAreRead() {
        XCTAssertEqual(Transcript.stampDate("today 9:41 am", taken: taken, calendar: calendar), at(6, 9, 41))
        XCTAssertEqual(Transcript.stampDate("9:41 pm", taken: taken, calendar: calendar), at(6, 21, 41))
        XCTAssertEqual(Transcript.stampDate("yesterday 12:05 am", taken: taken, calendar: calendar), at(5, 0, 5))
        XCTAssertEqual(Transcript.stampDate("tue 9:41 pm", taken: taken, calendar: calendar), at(3, 21, 41))
        XCTAssertEqual(Transcript.stampDate("fri 8:00 am", taken: taken, calendar: calendar), at(6, 8).addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(Transcript.stampDate("tue, nov 3 at 9:41 pm", taken: taken, calendar: calendar), at(3, 21, 41))
        XCTAssertEqual(Transcript.stampDate("nov 2, 2026 at 20:15", taken: taken, calendar: calendar), at(2, 20, 15))
        XCTAssertNil(Transcript.stampDate("see you at the park", taken: taken, calendar: calendar))
    }

    func testTimestampsOrderScreenshotsThatDontOverlap() {
        // Taken bottom of the chat first, then scrolled up a whole screen: no message repeats.
        let newer = [m(.them, "so friday?"), m(.you, "friday works")]
        let older = [m(.them, "hey there"), m(.you, "hi!")]
        let order = Transcript.chatOrder([newer, older], clues: [
            .init(first: at(6, 9), last: at(6, 9)), .init(first: at(5, 20), last: at(5, 20)),
        ])
        XCTAssertEqual(order, [1, 0])
    }

    func testDeliveredNoteMarksTheNewestScreenshot() {
        let newer = [m(.them, "so friday?"), m(.you, "friday works")]
        let older = [m(.them, "hey there"), m(.you, "hi!")]
        let order = Transcript.chatOrder([newer, older], clues: [.init(hasReceipt: true), .init()])
        XCTAssertEqual(order, [1, 0])
    }

    func testRepeatedMessagesStillWinAndNoCluesKeepsTakenOrder() {
        let older = [m(.them, "a"), m(.you, "b")]
        let newer = [m(.you, "b"), m(.them, "c")]
        XCTAssertEqual(Transcript.chatOrder([newer, older], clues: [.init(), .init(hasReceipt: true)]), [1, 0])
        XCTAssertEqual(Transcript.chatOrder([[m(.them, "x")], [m(.you, "y")]], clues: [.init(), .init()]), [0, 1])
    }

    func testTimestampsAndReceiptAreFoundOnScreen() {
        func line(_ t: String, y: CGFloat) -> TextLine { TextLine(text: t, box: CGRect(x: 0.4, y: y, width: 0.2, height: 0.02)) }
        let clues = BubbleLayout.timeClues([
            line("9:41", y: 0.01),                 // the status bar clock: ignored
            line("Today 9:41 PM", y: 0.20),
            line("Read 9:45 PM", y: 0.60),
        ])
        XCTAssertEqual(clues.stamps, ["today 9:41 pm"])
        XCTAssertTrue(clues.receipt)
    }
}

final class ScreenshotReorderTests: XCTestCase {
    private func m(_ s: Speaker, _ t: String) -> ChatMessage { ChatMessage(speaker: s, text: t) }

    func testDraggingAScreenshotJoinsTheChatInTheNewOrder() {
        let newer = [m(.them, "so friday?"), m(.you, "friday works")]
        let older = [m(.them, "hey there"), m(.you, "hi!")]
        let moved = Transcript.reorder([newer, older], from: 1, to: 0, keepingSpeakersOf: [])
        XCTAssertEqual(moved.joined.map(\.text), ["hey there", "hi!", "so friday?", "friday works"])
        XCTAssertEqual(moved.parts.map { $0.map(\.text) }, [["hey there", "hi!"], ["so friday?", "friday works"]])
    }

    func testSpeakersSwitchedByHandStaySwitched() {
        let a = [m(.them, "so friday?")]
        let b = [m(.them, "hey there")]
        let moved = Transcript.reorder([a, b], from: 0, to: 1, keepingSpeakersOf: [m(.you, "hey there")])
        XCTAssertEqual(moved.joined.map(\.speaker), [.you, .them])
    }

    func testThreeScreenshotsMiddleToFront() {
        let moved = Transcript.reorder([[m(.them, "a")], [m(.you, "b")], [m(.them, "c")]], from: 2, to: 0, keepingSpeakersOf: [])
        XCTAssertEqual(moved.joined.map(\.text), ["c", "a", "b"])
    }
}

final class ReplyHabitsTests: XCTestCase {
    private func pick(_ habits: inout ReplyHabits, _ mood: String?, times: Int = 1) {
        for _ in 0..<times { habits.pick(ReplySuggestion(text: "x", label: mood)) }
    }

    func testNoFavoriteUntilEnoughPicks() {
        var habits = ReplyHabits()
        pick(&habits, "playful", times: 4)
        XCTAssertNil(habits.favoriteMood)
        pick(&habits, "playful")
        XCTAssertEqual(habits.favoriteMood, "playful")
    }

    func testNoFavoriteWhenPicksAreSpread() {
        var habits = ReplyHabits()
        for mood in ["playful", "sweet", "bold", "chill", "funny", "flirty"] { pick(&habits, mood) }
        XCTAssertNil(habits.favoriteMood)
    }

    func testLabelsAreCountedIgnoringCase() {
        var habits = ReplyHabits()
        pick(&habits, "Sweet", times: 3)
        pick(&habits, nil, times: 2)
        XCTAssertEqual(habits.picks, 5)
        XCTAssertEqual(habits.moodPicks["sweet"], 3)
        XCTAssertEqual(habits.favoriteMood, "sweet")
    }
}

final class ReplySuggestionDecodingTests: XCTestCase {
    func testLabelIsOptional() throws {
        let json = #"[{"text": "dangerously confident tbh", "label": "playful"}, {"text": "coffee?"}]"#
        let replies = try JSONDecoder().decode([ReplySuggestion].self, from: Data(json.utf8))
        XCTAssertEqual(replies.map(\.text), ["dangerously confident tbh", "coffee?"])
        XCTAssertEqual(replies.map(\.label), ["playful", nil])
    }

    func testMoodTagsMatchTheEngine() {
        // engine/reply.py TONES; the tag row shows them in this order.
        XCTAssertEqual(ReplyTone.allCases.map(\.rawValue), ["funny", "flirty", "sweet", "chill", "bold", "shorter"])
        XCTAssertEqual(ReplyTone.allCases.map(\.label), ["Funny", "Flirty", "Sweet", "Chill", "Bold", "Shorter"])
    }
}

final class SayPickTests: XCTestCase {
    func testQuickPicksInOrderAndEachFitsTheLimit() {
        // Vanessa, Nov 7: plain "No" (the mood sets how nice it sounds).
        // The engine matches these exact intent lines (prompt v12).
        XCTAssertEqual(SayPick.allCases.map(\.intent), ["Say yes", "Say no", "Ask them out", "Change the topic"])
        XCTAssertEqual(SayPick.allCases.map(\.label), ["Yes", "No", "Ask them out", "Change topic"])
        XCTAssertEqual(Set(SayPick.allCases.map(\.intent)).count, SayPick.allCases.count)
        XCTAssertTrue(SayPick.allCases.allSatisfy { $0.intent.count <= 200 })  // ReplyFlowModel.maxIntent
    }

}
