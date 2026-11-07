import Foundation
import StoreKit

/// Who can get replies right now: the paywall's rules, kept on the phone only.
///
/// Two modes, so the free-tier A/B test (planned ~Feb, Vanessa Nov 7) is a switch, not a rebuild:
/// - A `freeDaysThenPay` (launch default): every reply is free for 3 days from the first
///   real chat, then a subscription is needed (it starts with Apple's 7-day free trial).
/// - B `dailyLimit`: free forever for 5 new chats a day; a subscription removes the limit.
///
/// The made-up example chat is always free. Asking again on a chat already read
/// (a mood tag, "Get new replies", "Tell Coax what to say") doesn't count as a new chat.
enum PaywallMode: String, Codable, CaseIterable {
    case freeDaysThenPay = "A"
    case dailyLimit = "B"
}

enum AccessPolicy {
    static let freeDays = 3
    static let freeChatsPerDay = 5
    /// Off until there are enough installs to split (~Feb). When on, each new install
    /// is put in A or B once, at random, and stays there.
    static let abTestOn = false
    /// Mode for installs before the test, and for everyone while it's off.
    static let launchMode: PaywallMode = .freeDaysThenPay
}

/// Why replies are paused.
enum AccessLock: Equatable {
    case freeDaysOver
    case dailyLimitReached

    /// Plain words for any screen that can't show the paywall itself.
    var message: String {
        switch self {
        case .freeDaysOver:
            return "Your \(AccessPolicy.freeDays) free days are over. Open Coax to keep getting replies."
        case .dailyLimitReached:
            return "That's your \(AccessPolicy.freeChatsPerDay) free chats for today. Open Coax for unlimited replies, or come back tomorrow."
        }
    }
}

enum AccessState: Equatable {
    case subscribed
    /// Mode A, inside the free days. `daysLeft` counts today.
    case freeDays(daysLeft: Int)
    /// Mode B, under today's limit.
    case freeToday(chatsLeft: Int)
    case locked(AccessLock)

    var lock: AccessLock? {
        if case .locked(let lock) = self { return lock }
        return nil
    }
}

/// What the free tier has used, on this phone.
struct UsageLedger: Codable, Equatable {
    /// The first real chat Coax wrote replies for (starts the free days).
    var firstUse: Date?
    /// Local calendar day of `chatsToday`, "2026-11-07".
    var day = ""
    var chatsToday = 0
}

/// The pure rules: given the mode, what's been used and whether the person
/// subscribes, may they get replies now? No storage, so it is easy to test.
struct AccessGate: Equatable {
    var mode: PaywallMode
    var ledger: UsageLedger
    var subscribed: Bool
    var calendar = Calendar.current

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func state(now: Date = Date()) -> AccessState {
        if subscribed { return .subscribed }
        switch mode {
        case .freeDaysThenPay:
            guard let first = ledger.firstUse else { return .freeDays(daysLeft: AccessPolicy.freeDays) }
            let free = TimeInterval(AccessPolicy.freeDays * 24 * 60 * 60)
            let left = free - now.timeIntervalSince(first)
            guard left > 0 else { return .locked(.freeDaysOver) }
            return .freeDays(daysLeft: Int((left / (24 * 60 * 60)).rounded(.up)))
        case .dailyLimit:
            let used = ledger.day == Self.dayKey(now, calendar) ? ledger.chatsToday : 0
            let left = AccessPolicy.freeChatsPerDay - used
            return left > 0 ? .freeToday(chatsLeft: left) : .locked(.dailyLimitReached)
        }
    }

    /// Count one new chat (call after its replies came back).
    mutating func recordNewChat(now: Date = Date()) {
        if ledger.firstUse == nil { ledger.firstUse = now }
        let today = Self.dayKey(now, calendar)
        if ledger.day != today {
            ledger.day = today
            ledger.chatsToday = 0
        }
        ledger.chatsToday += 1
    }
}

/// Where the paywall's state lives: this part of Coax's settings on the phone.
///
/// Note: until the App Group is set up (it needs the paid Apple Developer account),
/// the app, keyboard and Messages app each keep their own copy, so each has its own
/// free days. The subscription itself is read from Apple in each of them.
enum AccessStore {
    private static let modeKey = "coax.paywallMode"
    private static let ledgerKey = "coax.usageLedger"
    private static let subscribedUntilKey = "coax.subscribedUntil"

    static var defaults: UserDefaults { AgeSettings.defaults }

    private static let testPaywallKey = "coax.testPaywall"

    /// UI tests never hit the paywall. Builds run from Xcode (Debug) don't either, so
    /// Vanessa's own phone never locks, unless "Test the paywall" is turned on.
    static var isOff: Bool {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return true }
        #if DEBUG
        return !testPaywall
        #else
        return false
        #endif
    }

    /// Debug builds only: make the paywall rules apply, to try the paywall screen.
    static var testPaywall: Bool {
        get { defaults.bool(forKey: testPaywallKey) }
        set { defaults.set(newValue, forKey: testPaywallKey) }
    }

    /// This install's mode: picked once, then kept.
    static var mode: PaywallMode {
        if let saved = defaults.string(forKey: modeKey).flatMap(PaywallMode.init(rawValue:)) { return saved }
        let picked: PaywallMode = AccessPolicy.abTestOn ? (Bool.random() ? .freeDaysThenPay : .dailyLimit)
                                                        : AccessPolicy.launchMode
        defaults.set(picked.rawValue, forKey: modeKey)
        return picked
    }

    static var ledger: UsageLedger {
        get {
            guard let data = defaults.data(forKey: ledgerKey),
                  let saved = try? JSONDecoder().decode(UsageLedger.self, from: data) else { return UsageLedger() }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: ledgerKey) }
    }

    /// When the current subscription period ends, as last seen from Apple (nil = none).
    static var subscribedUntil: Date? {
        get { defaults.object(forKey: subscribedUntilKey) as? Date }
        set { defaults.set(newValue, forKey: subscribedUntilKey) }
    }

    static func gate(now: Date = Date()) -> AccessGate {
        AccessGate(mode: mode, ledger: ledger, subscribed: (subscribedUntil ?? .distantPast) > now)
    }

    static func state(now: Date = Date()) -> AccessState {
        isOff ? .subscribed : gate(now: now).state(now: now)
    }

    /// Before saying no, ask Apple once whether a subscription started or renewed
    /// (bought in the app, or on another device) since it was last checked.
    static func check(now: Date = Date()) async -> AccessState {
        let first = state(now: now)
        guard first.lock != nil else { return first }
        await Entitlements.refresh()
        return state(now: now)
    }

    static func recordNewChat(now: Date = Date()) {
        guard !isOff else { return }
        var g = gate(now: now)
        g.recordNewChat(now: now)
        ledger = g.ledger
    }

    static func reset() {
        for key in [modeKey, ledgerKey, subscribedUntilKey, testPaywallKey] { defaults.removeObject(forKey: key) }
    }
}

/// The subscription, read from Apple (StoreKit 2). Works in the app and its extensions;
/// buying happens only in the app (see Purchases).
enum Entitlements {
    static let weeklyID = "com.vchev.coax.weekly"
    static let yearlyID = "com.vchev.coax.yearly"
    static let productIDs = [weeklyID, yearlyID]

    /// Reads the current entitlements and saves when the subscription ends.
    static func refresh() async {
        var until: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, productIDs.contains(t.productID),
                  t.revocationDate == nil else { continue }
            let end = t.expirationDate ?? .distantFuture
            if until.map({ end > $0 }) ?? true { until = end }
        }
        AccessStore.subscribedUntil = until
    }
}
