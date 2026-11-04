import XCTest

final class AgeSettingsTests: XCTestCase {
    func testTeenRepliesOnlyForUnder18() {
        let saved = AgeSettings.ageGroup
        defer { AgeSettings.ageGroup = saved }
        AgeSettings.ageGroup = .teen
        XCTAssertTrue(AgeSettings.wantsTeenReplies)
        AgeSettings.ageGroup = .adult
        XCTAssertFalse(AgeSettings.wantsTeenReplies)
    }
}
