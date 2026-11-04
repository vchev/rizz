import Foundation

/// The user's age group and onboarding progress, kept on the phone only.
///
/// Coax is 16+. Ages 16-17 get teen mode: the reply engine is told the user is
/// under 18, so it never suggests anything sexual (`under_18` in the request).
///
/// Stored in the app group's defaults when one is set up (CoaxAppGroup in
/// Info.plist), so the keyboard and the Messages app see the same answer.
/// Until then it falls back to the app's own defaults, which the Back Tap
/// shortcut and the app itself read.
enum AgeGroup: String, Codable {
    case under16, teen, adult
}

enum AgeSettings {
    private static let groupKey = "coax.ageGroup"
    private static let sourceKey = "coax.ageSource"
    private static let parentOKKey = "coax.parentOK"
    private static let onboardedKey = "coax.onboarded"

    static var defaults: UserDefaults {
        if let id = Bundle.main.object(forInfoDictionaryKey: "CoaxAppGroup") as? String, !id.isEmpty,
           let shared = UserDefaults(suiteName: id) {
            return shared
        }
        return .standard
    }

    static var ageGroup: AgeGroup? {
        get { defaults.string(forKey: groupKey).flatMap(AgeGroup.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: groupKey) }
    }

    /// "apple" when it came from Apple's Declared Age Range, "tapped" when the user picked it.
    static var source: String? {
        get { defaults.string(forKey: sourceKey) }
        set { defaults.set(newValue, forKey: sourceKey) }
    }

    /// When a parent or guardian said yes (16-17 only).
    static var parentOK: Date? {
        get { defaults.object(forKey: parentOKKey) as? Date }
        set { defaults.set(newValue, forKey: parentOKKey) }
    }

    static var onboarded: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }

    /// Ask the reply engine for teen-safe replies (16-17).
    /// The keyboard and Messages app can't see the answer until the app group
    /// is set up (needs the paid Apple account), so for now they leave it off.
    static var wantsTeenReplies: Bool {
        ageGroup == .teen || ageGroup == .under16
    }

    static func reset() {
        for key in [groupKey, sourceKey, parentOKKey, onboardedKey] { defaults.removeObject(forKey: key) }
    }
}
