import XCTest

final class VoiceProfileTests: XCTestCase {
    private func mine(_ texts: [String]) -> [ChatMessage] {
        texts.map { ChatMessage(speaker: .you, text: $0) }
    }

    func testOnlyOwnNewMessagesAreCounted() {
        var profile = VoiceProfile()
        let chat = [ChatMessage(speaker: .them, text: "how was your week"),
                    ChatMessage(speaker: .you, text: "honestly long"),
                    ChatMessage(speaker: .you, text: "friday is carrying me")]
        XCTAssertEqual(profile.learn(from: chat), 2)
        // The same messages from an overlapping screenshot don't count twice.
        XCTAssertEqual(profile.learn(from: chat), 0)
        XCTAssertEqual(profile.messageCount, 2)
        XCTAssertEqual(profile.recent, ["honestly long", "friday is carrying me"])
    }

    func testExampleChatIsIgnored() {
        var profile = VoiceProfile()
        XCTAssertEqual(profile.learn(from: ChatMessage.example, ignoring: VoiceSettings.ignoredTexts), 0)
    }

    func testQuizAloneUntilEnoughMessages() {
        var profile = VoiceProfile()
        profile.quiz = ["length": 0.9]
        profile.learn(from: mine(["ok", "ya", "lol same"]))
        XCTAssertEqual(profile.value(.length), 0.9, accuracy: 0.001)   // under 5 messages: quiz only
    }

    func testMessagesPullTheQuizTowardReality() {
        var profile = VoiceProfile()
        profile.quiz = ["length": 0.9, "caps": 0.9]
        profile.learn(from: mine((1...40).map { "ok \($0)" }))        // 40 two-word lowercase texts
        XCTAssertLessThan(profile.value(.length), 0.3)
        XCTAssertLessThan(profile.value(.caps), 0.3)
        XCTAssertEqual(profile.surprise, "You text shorter than you said")
        XCTAssertTrue(profile.chips.contains("short replies"))

        var backToQuiz = profile
        backToQuiz.trustQuiz = true
        XCTAssertEqual(backToQuiz.value(.length), 0.9, accuracy: 0.001)
        XCTAssertNil(backToQuiz.surprise)

        profile.acceptLearned()
        XCTAssertNil(profile.surprise)
    }

    func testQuizAsksOnlyWhatTextsCantShow() {
        XCTAssertEqual(VoiceTrait.quizTraits, [.humour, .forward, .looking])
        var profile = VoiceProfile()
        profile.quiz = ["humour": 0.8, "forward": 0.5, "looking": 0.2]
        XCTAssertEqual(profile.shownTraits, [.humour, .forward, .looking])
        profile.learn(from: mine((1...10).map { "ok \($0)" }))
        // Not asked, so the texts alone decide, and the card never says "than you said".
        XCTAssertEqual(profile.value(.length), 0, accuracy: 0.001)
        XCTAssertTrue(profile.shownTraits.contains(.length))
        XCTAssertNil(profile.surprise)
        XCTAssertEqual(profile.payload?.looking, 0.2)
    }

    func testSamplePickSeedsWhatTextsWillLearn() {
        var profile = VoiceProfile()
        profile.quiz = StyleSample.all[0].answers
        XCTAssertEqual(profile.value(.length), 0.1, accuracy: 0.001)
        XCTAssertEqual(profile.payload?.caps, 0)
        XCTAssertEqual(Set(StyleSample.all.flatMap { $0.answers.keys }), ["length", "caps", "emoji"])
    }

    func testPayloadOnlyWhenThereIsSomething() {
        XCTAssertNil(VoiceProfile().payload)
        var profile = VoiceProfile()
        profile.quiz = ["humour": 0.8]
        let payload = profile.payload
        XCTAssertEqual(payload?.humour, 0.8)
        XCTAssertNil(payload?.length)
        XCTAssertEqual(payload?.examples, [])
    }

    func testOffMeansNoVoiceInRequests() {
        let saved = VoiceSettings.isEnabled
        defer { VoiceSettings.isEnabled = saved }
        VoiceSettings.isEnabled = false
        XCTAssertNil(VoiceSettings.voiceForRequest(learningFrom: mine(["hey"])))
    }

    func testRequestLeavesVoiceOutWhenNil() throws {
        let body = HTTPReplyService.RequestBody(platform: "imessage", n: 3, tone: nil,
                                                messages: mine(["hey"]), replyingTo: nil)
        let json = String(data: try JSONEncoder().encode(body), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("voice"))
    }
}
