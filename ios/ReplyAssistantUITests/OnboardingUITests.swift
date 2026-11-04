import XCTest

/// Walks through first-run setup in the simulator. The age is picked by tapping.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-onboarding"]
        app.launch()
        return app
    }

    private func pickAge(_ app: XCUIApplication, _ answer: String) {
        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        save(app, "onboarding-1-welcome")
        start.tap()
        let button = app.buttons[answer]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Age buttons should show right away")
        save(app, "onboarding-2-age")
        button.tap()
    }

    func testAdultSeesARealReplyThenSetsUpKeyboard() throws {
        let app = launch()
        pickAge(app, "I'm 18 or older")

        let reply = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Sample reply")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "Replies should appear in the first minute")
        save(app, "onboarding-3-first-reply")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.staticTexts["Your replies wait in the Coax keyboard"].waitForExistence(timeout: 5))
        save(app, "onboarding-4-full-access")
        app.buttons["Next"].tap()

        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        save(app, "onboarding-5-keyboard")
        skip.tap()

        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        save(app, "onboarding-6-photos")
        notNow.tap()

        XCTAssertTrue(app.navigationBars["Coax"].waitForExistence(timeout: 5), "Main screen after setup")
    }

    func testUnder16IsTurnedAway() throws {
        let app = launch()
        pickAge(app, "I'm under 16")
        XCTAssertTrue(app.staticTexts["Coax is for people 16 and older"].waitForExistence(timeout: 5))
        save(app, "onboarding-under-16")
    }

    func testSixteenOrSeventeenAsksForParentOK() throws {
        let app = launch()
        pickAge(app, "I'm 16 or 17")
        let ok = app.buttons["My parent or guardian said OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 5))
        save(app, "onboarding-teen-parent")
        ok.tap()
        let reply = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Sample reply")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30))
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
