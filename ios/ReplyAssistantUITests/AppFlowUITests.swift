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

        let example = app.buttons["Try it with an example chat"]
        if !example.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        example.tap()

        let reply = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Sample reply")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "Replies should appear")
        save(app, "2-replies")

        reply.tap()
        save(app, "3-after-copy")

        app.buttons["Fix the chat"].tap()
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
