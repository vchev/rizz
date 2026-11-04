import UIKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Asks iOS for the user's age range with Apple's Declared Age Range
/// (iOS 26 and later). iOS shows its own sheet and only ever tells Coax a
/// range (under 16, 16-17, 18+), never a birthday.
///
/// Returns nil when it can't tell: older iOS, the user declined to share,
/// or the app isn't allowed to ask yet (the Declared Age Range capability
/// needs the paid Apple Developer account). Onboarding then asks the user to tap their age.
enum AgeCheck {
    /// Off until the Declared Age Range capability is added (paid account).
    /// Without it, iOS never answers, so asking would just wait.
    static let isEnabled = false

    /// Apple's answer, or nil if it doesn't come within `timeout` seconds.
    /// (A task group would wait for the stuck request, so this races two tasks instead.)
    @MainActor
    static func askApple(timeout: Double) async -> AgeGroup? {
        await withCheckedContinuation { (done: CheckedContinuation<AgeGroup?, Never>) in
            let once = Once()
            Task { @MainActor in
                let answer = await askAppleNoLimit()
                once.run { done.resume(returning: answer) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                once.run { done.resume(returning: nil) }
            }
        }
    }

    @MainActor
    private final class Once {
        private var used = false
        func run(_ body: () -> Void) {
            guard !used else { return }
            used = true
            body()
        }
    }

    @MainActor
    private static func askAppleNoLimit() async -> AgeGroup? {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            guard let host = topViewController() else { return nil }
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 16, 18, in: host)
                guard case let .sharing(range) = response else { return nil }
                guard let lower = range.lowerBound else { return .under16 }
                return lower >= 18 ? .adult : (lower >= 16 ? .teen : .under16)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Whether the Coax keyboard has been added in Settings > Keyboards.
/// (Full Access can't be checked from the app; the keyboard says so itself.)
enum KeyboardCheck {
    static let keyboardID = (Bundle.main.bundleIdentifier ?? "com.vchev.ReplyAssistant") + ".Keyboard"

    static var isAdded: Bool {
        let added = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        return added.contains(keyboardID)
    }
}
