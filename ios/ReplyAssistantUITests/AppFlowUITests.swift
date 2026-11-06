import XCTest

/// Runs the real app in the simulator: example chat in, replies out.
final class AppFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testExampleChatShowsReplies() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        save(app, "1-home")

        // The link sits at the bottom of Home, under the how-to card and the
        // setup banner; scroll until it can really be tapped.
        let example = app.buttons["Try it with an example chat"]
        XCTAssertTrue(example.waitForExistence(timeout: 10))
        var swipes = 0
        while !example.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        example.tap()
        XCTAssertTrue(app.staticTexts["Pick a reply"].waitForExistence(timeout: 10), "Tapping the example opens Replies")

        let reply = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Sample reply")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "Replies should appear")
        save(app, "2-replies")

        reply.tap()
        save(app, "3-after-copy")

        let fix = app.buttons["Fix the chat"]
        XCTAssertTrue(fix.waitForExistence(timeout: 5), "Fix the chat should show above the replies")
        fix.tap()
        XCTAssertTrue(app.navigationBars["Fix the chat"].waitForExistence(timeout: 5))
        save(app, "4-fix-the-chat")
    }

    /// Keeps screenshots in the test results; also writes PNGs to SCREENSHOT_DIR when set.
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
