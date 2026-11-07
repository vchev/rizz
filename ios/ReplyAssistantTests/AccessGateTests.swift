import XCTest

final class AccessGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func hours(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }

    func testFreeDaysStartAtTheFirstChatThenLock() {
        var gate = AccessGate(mode: .freeDaysThenPay, ledger: UsageLedger(), subscribed: false, calendar: utc)
        XCTAssertEqual(gate.state(now: start), .freeDays(daysLeft: 3))
        gate.recordNewChat(now: start)
        XCTAssertEqual(gate.state(now: hours(1)), .freeDays(daysLeft: 3))
        XCTAssertEqual(gate.state(now: hours(25)), .freeDays(daysLeft: 2))
        XCTAssertEqual(gate.state(now: hours(71.9)), .freeDays(daysLeft: 1))
        XCTAssertEqual(gate.state(now: hours(72)), .locked(.freeDaysOver))
        // More chats don't move the start.
        gate.recordNewChat(now: hours(50))
        XCTAssertEqual(gate.ledger.firstUse, start)
    }

    func testDailyLimitResetsEachDay() {
        var gate = AccessGate(mode: .dailyLimit, ledger: UsageLedger(), subscribed: false, calendar: utc)
        for i in 0..<AccessPolicy.freeChatsPerDay {
            XCTAssertEqual(gate.state(now: hours(1)), .freeToday(chatsLeft: AccessPolicy.freeChatsPerDay - i))
            gate.recordNewChat(now: hours(1))
        }
        XCTAssertEqual(gate.state(now: hours(2)), .locked(.dailyLimitReached))
        // Next calendar day: a fresh allowance, and the days never run out in this mode.
        XCTAssertEqual(gate.state(now: hours(24 * 30)), .freeToday(chatsLeft: AccessPolicy.freeChatsPerDay))
    }

    func testSubscribersAreNeverLocked() {
        var ledger = UsageLedger()
        ledger.firstUse = hours(-24 * 10)
        ledger.day = AccessGate.dayKey(start, utc)
        ledger.chatsToday = 99
        for mode in PaywallMode.allCases {
            XCTAssertEqual(AccessGate(mode: mode, ledger: ledger, subscribed: true, calendar: utc).state(now: start), .subscribed)
            XCTAssertNotNil(AccessGate(mode: mode, ledger: ledger, subscribed: false, calendar: utc).state(now: start).lock)
        }
    }

    func testLaunchDefaultIsFreeDaysThenPay() {
        XCTAssertFalse(AccessPolicy.abTestOn)
        XCTAssertEqual(AccessPolicy.launchMode, .freeDaysThenPay)
        XCTAssertEqual(AccessPolicy.freeDays, 3)
        XCTAssertEqual(AccessLock.freeDaysOver.message.contains("3 free days"), true)
    }
}
