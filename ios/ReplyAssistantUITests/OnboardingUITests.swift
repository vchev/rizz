import XCTest

/// Walks through first-run setup in the simulator: Try it, Photos, Keyboard,
/// You're set, then Home. There's no age screen; "-appleAge" stands in for Apple's age range.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(appleAge: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-onboarding"] + (appleAge.map { ["-appleAge", $0] } ?? [])
        app.launch()
        return app
    }

    private func sampleReply(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Sample reply")).firstMatch
    }

    func testAdultSeesARealReplyThenSetsUp() throws {
        let app = launch()

        // 1. Try it: a reply in the first minute, before any setup.
        let reply = sampleReply(app)
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "Replies should appear in the first minute")
        save(app, "onboarding-1-try-it")
        reply.tap()
        save(app, "onboarding-1b-reply-in-message-box")
        app.buttons["Set it up · 1 minute"].tap()

        // 2. Photos, inside the app, with consent naming the AI.
        XCTAssertTrue(app.staticTexts["Replies are written by a third-party AI"].waitForExistence(timeout: 5))
        save(app, "onboarding-2-photos")
        // Agreeing shows the result before moving on (no silent jump).
        app.buttons["Agree and allow Photos"].tap()
        XCTAssertTrue(app.staticTexts["Photos is on"].waitForExistence(timeout: 5), "Photos result shows")
        save(app, "onboarding-2b-photos-on")
        app.buttons["Next"].tap()

        // 3. Keyboard: one trip to Settings.
        XCTAssertTrue(app.staticTexts["Add the Coax keyboard"].waitForExistence(timeout: 5))
        save(app, "onboarding-3-keyboard")
        app.buttons["Later"].tap()

        // 4. You're set: a clear end, with the three taps.
        XCTAssertTrue(app.staticTexts["You're set"].waitForExistence(timeout: 5), "Setup ends on You're set")
        save(app, "onboarding-4-done")
        app.buttons["Start using Coax"].tap()

        // Home.
        XCTAssertTrue(app.buttons["Get replies from a screenshot"].waitForExistence(timeout: 5), "Home after setup")
        XCTAssertTrue(app.staticTexts["Here's the move"].exists)
        save(app, "home-first-visit")
    }

    func testBackGoesToThePreviousStep() throws {
        let app = launch()
        let setUp = app.buttons["Set it up · 1 minute"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 30))
        setUp.tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(setUp.waitForExistence(timeout: 5))
    }

    func testUnder16IsTurnedAway() throws {
        let app = launch(appleAge: "under16")
        XCTAssertTrue(app.staticTexts["Coax is for people 16 and older"].waitForExistence(timeout: 10))
        save(app, "onboarding-under-16")

        // Test builds can start over from here.
        app.buttons["Start over (test builds only)"].tap()
        XCTAssertTrue(app.buttons["Set it up · 1 minute"].waitForExistence(timeout: 5))
    }

    func testSetupCanBeReplayedFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]   // already set up: Home
        app.launch()
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        save(app, "settings")
        let replay = app.buttons["Show setup again"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.buttons["Set it up · 1 minute"].waitForExistence(timeout: 10))
    }

    func testSixteenOrSeventeenAsksForParentOK() throws {
        let app = launch(appleAge: "teen")
        let ok = app.buttons["My parent or guardian said OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 10))
        save(app, "onboarding-teen-parent")
        ok.tap()
        XCTAssertTrue(sampleReply(app).waitForExistence(timeout: 30))
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
