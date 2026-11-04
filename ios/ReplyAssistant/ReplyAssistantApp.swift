import SwiftUI

@main
struct ReplyAssistantApp: App {
    @State private var onboarded: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarding") {
            // UI tests: start fresh and walk through onboarding.
            AgeSettings.reset()
        } else if args.contains("-uiTesting") {
            // Other UI tests go straight to the main screen.
            AgeSettings.onboarded = true
        }
        _onboarded = State(initialValue: AgeSettings.onboarded && AgeSettings.ageGroup != .under16)
    }

    var body: some Scene {
        WindowGroup {
            if onboarded {
                ContentView(onReplaySetup: {
                    AgeSettings.reset()
                    onboarded = false
                })
            } else {
                OnboardingView { onboarded = true }
            }
        }
    }
}
