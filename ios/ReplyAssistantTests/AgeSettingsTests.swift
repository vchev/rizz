import XCTest

final class AgeSettingsTests: XCTestCase {
    func testBirthYearGroups() {
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2016, currentYear: 2026), .under16)
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2011, currentYear: 2026), .under16)  // 14 or 15
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2009, currentYear: 2026), .teen)     // 16 or 17
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 1996, currentYear: 2026), .adult)
    }

    func testBoundaryYearsNeedTheBirthday() {
        XCTAssertNil(AgeFromBirthYear.group(birthYear: 2010, currentYear: 2026))   // 15 or 16
        XCTAssertNil(AgeFromBirthYear.group(birthYear: 2008, currentYear: 2026))   // 17 or 18
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2010, currentYear: 2026, hadBirthdayThisYear: true), .teen)
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2010, currentYear: 2026, hadBirthdayThisYear: false), .under16)
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2008, currentYear: 2026, hadBirthdayThisYear: true), .adult)
        XCTAssertEqual(AgeFromBirthYear.group(birthYear: 2008, currentYear: 2026, hadBirthdayThisYear: false), .teen)
    }

    func testTeenRepliesOnlyForUnder18() {
        let saved = AgeSettings.ageGroup
        defer { AgeSettings.ageGroup = saved }
        AgeSettings.ageGroup = .teen
        XCTAssertTrue(AgeSettings.wantsTeenReplies)
        AgeSettings.ageGroup = .adult
        XCTAssertFalse(AgeSettings.wantsTeenReplies)
    }
}
