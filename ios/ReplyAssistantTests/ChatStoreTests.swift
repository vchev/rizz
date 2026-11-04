import XCTest

private func m(_ s: Speaker, _ t: String) -> ChatMessage { ChatMessage(speaker: s, text: t) }

/// Joining overlapping screenshots when text recognition isn't word-perfect.
final class TranscriptStitchingTests: XCTestCase {
    func testSmallMisreadsStillCountAsTheSameMessage() {
        let first = [m(.them, "hi"), m(.you, "I took one pottery class and now I think I'm a ceramicist"),
                     m(.them, "honestly iconic, what did you make")]
        let second = [m(.you, "I took one pottery dass and now I think Im a ceramicist"),
                      m(.them, "honestly iconic. what did you make?"), m(.you, "a bowl that is also a plate")]
        XCTAssertEqual(Transcript.append(second, to: first).map(\.text).count, 4)
    }

    func testABubbleCutOffAtTheScreenEdgeIsKeptOnceAndWhole() {
        // The first screenshot ends mid-bubble; the second starts with the rest of it.
        let whole = "there is a night market downtown on Saturday and I heard the dumplings are great"
        let first = [m(.them, "are you free this weekend"), m(.you, "maybe, what did you have in mind"),
                     m(.them, "there is a night market downtown on Saturday")]
        let second = [m(.them, whole), m(.you, "I'm in"), m(.them, "7pm?")]
        let joined = Transcript.append(second, to: first)
        XCTAssertEqual(joined.map(\.text), ["are you free this weekend", "maybe, what did you have in mind",
                                            whole, "I'm in", "7pm?"])

        // The second screenshot starts with only the end of a bubble.
        let tail = [m(.them, "the dumplings are great"), m(.you, "I'm in")]
        let full = [m(.you, "maybe, what did you have in mind"), m(.them, whole)]
        XCTAssertEqual(Transcript.append(tail, to: full).map(\.text),
                       ["maybe, what did you have in mind", whole, "I'm in"])
    }

    func testShortDifferentMessagesAreNotMerged() {
        XCTAssertFalse(Transcript.similar("ok", "no"))
        XCTAssertFalse(Transcript.similar("see you at 7", "see you at 8"))
        XCTAssertTrue(Transcript.similar("See you at 7!", "see you at 7"))
    }
}

final class SameChatTests: XCTestCase {
    func testAnOldScreenshotOfAnotherChatIsLeftOut() {
        let now = Date()
        let otherChat = [m(.them, "are we still on for pickleball tomorrow"), m(.you, "yes 9am")]
        let thisChat = [m(.them, "Btw! I'm sure you get this a lot but you have a really nice smile")]
        XCTAssertEqual(Transcript.sameChat([otherChat, thisChat], taken: [now.addingTimeInterval(-3600), now]), [1])
    }

    func testOverlappingOrBackToBackScreenshotsAreKept() {
        let now = Date()
        let older = [m(.them, "are you free this weekend"), m(.you, "maybe, what did you have in mind")]
        let newer = [m(.you, "maybe, what did you have in mind"), m(.them, "night market on Saturday?")]
        XCTAssertEqual(Transcript.sameChat([older, newer], taken: [now.addingTimeInterval(-3600), now]), [0, 1])
        let noOverlap = [m(.them, "how was your trip"), m(.you, "amazing, the food was unreal")]
        XCTAssertEqual(Transcript.sameChat([noOverlap, newer], taken: [now.addingTimeInterval(-20), now]), [0, 1])
    }
}

final class ChatStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("chats-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testANewScreenshotAddsToTheSameChat() {
        let store = ChatStore(url: url)
        let first = store.remember([m(.them, "are you free this weekend"), m(.you, "maybe, what did you have in mind"),
                                    m(.them, "night market on Saturday?")])
        let second = store.remember([m(.you, "maybe, what did you have in mind"), m(.them, "night market on Saturday?"),
                                     m(.you, "I'm in")])
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.messages.map(\.text), ["are you free this weekend", "maybe, what did you have in mind",
                                                     "night market on Saturday?", "I'm in"])
        XCTAssertEqual(store.chats.count, 1)
    }

    func testDifferentPeopleGetDifferentChats() {
        let store = ChatStore(url: url)
        store.remember([m(.them, "hey"), m(.you, "lol"), m(.them, "how was the hike with your sister")])
        store.remember([m(.them, "hey"), m(.you, "lol")])
        store.remember([m(.them, "want to get tacos on Thursday"), m(.you, "yes please")])
        XCTAssertEqual(store.chats.count, 3, "Two short lines in common shouldn't join two people's chats")
    }

    func testAFixedSpeakerStaysFixed() {
        let store = ChatStore(url: url)
        let chat = store.remember([m(.them, "I played pickleball 3 times"), m(.them, "are you really good or what")])
        var fixed = chat.messages
        fixed[0].speaker = .you
        fixed[1].speaker = .you
        store.update(chat.id, messages: fixed)
        // The next screenshot misreads them the same way again.
        let next = store.remember([m(.them, "I played pickleball 3 times"), m(.them, "are you really good or what"),
                                   m(.them, "when are you usually free")])
        XCTAssertEqual(next.messages.map(\.speaker), [.you, .you, .them])
    }

    func testScrollingUpPutsOlderMessagesFirst() {
        let store = ChatStore(url: url)
        store.remember([m(.them, "night market on Saturday?"), m(.you, "I'm in"), m(.them, "7pm at the north gate")])
        let chat = store.remember([m(.them, "are you free this weekend"), m(.you, "maybe, what did you have in mind"),
                                   m(.them, "night market on Saturday?"), m(.you, "I'm in")])
        XCTAssertEqual(chat.messages.map(\.text), ["are you free this weekend", "maybe, what did you have in mind",
                                                   "night market on Saturday?", "I'm in", "7pm at the north gate"])
    }

    func testChatsAreKeptBetweenLaunchesAndForgottenAfter30Days() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        ChatStore(url: url).remember([m(.them, "how was the hike with your sister")], key: "a", now: start)
        let reopened = ChatStore(url: url)
        XCTAssertEqual(reopened.chat("a")?.messages.map(\.text), ["how was the hike with your sister"])
        reopened.remember([m(.them, "something else entirely, new person")], key: "b",
                          now: start.addingTimeInterval(31 * 24 * 3600))
        XCTAssertNil(reopened.chat("a"))
        reopened.forgetAll()
        XCTAssertTrue(ChatStore(url: url).chats.isEmpty)
    }

    func testTheLatestScreenshotLandsWhereItBelongsAndIsMarked() {
        let store = ChatStore(url: url)
        store.remember([m(.them, "are you free this weekend"), m(.you, "maybe, what did you have in mind"),
                        m(.them, "night market on Saturday?"), m(.you, "I'm in"), m(.them, "7pm at the north gate")])
        // Scrolled up a little: the read is the middle of the saved chat, with one line misread.
        let chat = store.remember([m(.you, "maybe, what did you have in mlnd"), m(.them, "night market on Saturday?")])
        XCTAssertEqual(chat.messages.count, 5)
        XCTAssertEqual(chat.latest, 1..<3)
    }

    func testAShortRepeatedLineDoesNotThrowAwayTheChat() {
        let store = ChatStore(url: url)
        let long = (1...6).map { m($0 % 2 == 0 ? .you : .them, "message number \($0) about the hike we planned") }
        store.remember([m(.them, "lol")] + long, key: "k")
        let chat = store.remember([m(.you, "lol"), m(.them, "see you saturday then, can't wait")], key: "k")
        XCTAssertEqual(chat.messages.count, 9, "Saved messages must survive a stray 'lol' match")
        XCTAssertEqual(chat.messages.last?.text, "see you saturday then, can't wait")
    }

    func testAKeyKeepsEachMessagesChatSeparate() {
        let store = ChatStore(url: url)
        let a = store.remember([m(.them, "how was the hike with your sister")], key: "messages:1")
        let b = store.remember([m(.them, "how was the hike with your sister")], key: "messages:2")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(store.remember([m(.you, "so good")], key: "messages:1").messages.count, 2)
    }
}
