import SwiftUI
import UIKit

/// First-run setup, three screens (design review, Nov 5):
/// 1. Try it: a real reply to an example chat, before any setup.
/// 2. Photos, asked inside the app, with consent to send chat text to the AI.
/// 3. Add the Coax keyboard: one trip to Coax's page in Settings.
/// 4. You're set: what's on, the three taps, and the optional style quiz.
/// Then Home.
///
/// Apple's age range (once switched on) still runs quietly in the background:
/// it can turn away under-16s or ask 16-17s for a parent's OK.
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Step: Equatable {
        case tryIt, keyboard, photos, done
        case checkingAge, turnedAway, parentOK
    }

    @State private var step: Step
    @State private var ageChecked = false
    /// Photos access after tapping Agree (nil = not asked on this screen yet).
    @State private var photosOn: Bool?
    @State private var showVoice = false
    @Environment(\.scenePhase) private var scenePhase

    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// UI tests stand in for Apple's answer with "-appleAge teen" (or adult, under16).
    private static var testAppleAge: AgeGroup? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-appleAge"), i + 1 < args.count else { return nil }
        return AgeGroup(rawValue: args[i + 1])
    }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: Self.resumeStep())
    }

    /// Picks up where the user left off (a turned-away user stays turned away).
    static func resumeStep() -> Step {
        switch AgeSettings.ageGroup {
        case .under16: return .turnedAway
        case .teen where AgeSettings.parentOK == nil: return .parentOK
        default: return .tryIt
        }
    }

    var body: some View {
        Group {
            switch step {
            case .tryIt: TryItStep { go(.photos) }
            case .keyboard: keyboard
            case .photos: photos
            case .done: done
            case .checkingAge: checkingAge
            case .turnedAway: turnedAway
            case .parentOK: parentOK
            }
        }
        .animation(.default, value: step)
        .tint(Color.coax)
        .task { checkAge() }
    }

    private func go(_ next: Step) { withAnimation { step = next } }

    // MARK: Age (no age screen; decided Nov 4)

    /// The App Store's 16+ rating gates downloads. Apple's age range, once switched
    /// on (paid developer account), quietly sets teen mode or turns away under-16s,
    /// with a time limit so it can never hang. No answer = carry on.
    private func checkAge() {
        guard !ageChecked, AgeSettings.ageGroup == nil else { return }
        ageChecked = true
        if uiTesting {
            if let group = Self.testAppleAge { set(group) }
            return
        }
        guard AgeCheck.isEnabled else { return }
        Task {
            if let group = await AgeCheck.askApple(timeout: 3) {
                AgeSettings.source = "apple"
                set(group)
            }
        }
    }

    private func set(_ group: AgeGroup) {
        AgeSettings.ageGroup = group
        switch group {
        case .under16: go(.turnedAway)
        case .teen: go(.parentOK)
        case .adult: break
        }
    }

    // MARK: Setup screens

    /// After Photos: skip the keyboard step when it's already on (setup replayed).
    private func afterPhotos() {
        if KeyboardCheck.isAdded && RecentScreenshots.hasFullAccess { go(.done) } else { go(.keyboard) }
    }

    /// One trip to Settings: Coax's own page holds Keyboards (and Photos, if
    /// only some photos were allowed).
    private var keyboard: some View {
        SetupPage(step: 2, onBack: { go(.photos) }, skipTitle: "Later", onSkip: { go(.done) }) {
            ScreenTitle(title: "Add the Coax keyboard",
                        subtitle: "One trip to Settings, about 30 seconds. Coax moves on by itself when you come back.")
            SettingsPicture(fixPhotos: RecentScreenshots.isLimited)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color.coax)
                Text("iPhone warns about Full Access for every keyboard. **Coax never saves what you type.** It only uses the internet to fetch replies.")
                    .font(.subheadline)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.coaxSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } bottom: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(PrimaryButton())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, step == .keyboard, KeyboardCheck.isAdded { go(.done) }
        }
    }

    /// Asked inside the app first: one tap on iPhone's own prompt, no searching.
    private var photos: some View {
        SetupPage(step: 1, onBack: { go(.tryIt) }, skipTitle: "Not now", onSkip: { afterPhotos() }) {
            ScreenTitle(title: "Screenshot the chat. Coax does the rest.",
                        subtitle: "Coax needs Photos to see your newest screenshot. On the next prompt, tap Allow Full Access.")
            ScreenshotPicture()
            VStack(alignment: .leading, spacing: 10) {
                Promise(icon: "iphone", text: "Screenshots are read on your iPhone")
                Promise(icon: "checkmark", text: "Only the chat text is sent, never the image")
                Promise(icon: "checkmark", text: "Replies come from a trusted third-party AI that never trains on your chats")
                Promise(icon: "checkmark", text: "Nothing is kept")
            }
        } bottom: {
            VStack(spacing: 10) {
                if let on = photosOn {
                    PhotosResult(on: on)
                    Button("Next") { afterPhotos() }
                        .buttonStyle(PrimaryButton())
                } else {
                    Button("Agree and allow Photos") {
                        Task {
                            if !uiTesting { _ = await RecentScreenshots.requestAccess() }
                            // iPhone only asks once; if it was already allowed there's no prompt,
                            // so say what happened instead of jumping ahead.
                            photosOn = uiTesting ? true : RecentScreenshots.hasFullAccess
                        }
                    }
                    .buttonStyle(PrimaryButton())
                }
            }
        }
    }

    /// The end of setup: what's on, the three taps, and the optional style quiz.
    private var done: some View {
        SetupPage(step: 0, onBack: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.coaxDone)
                ScreenTitle(title: "You're set", subtitle: "Here's the move next time someone texts you.")
            }
            VStack(alignment: .leading, spacing: 8) {
                SetupStatus(title: "Photos", on: uiTesting || RecentScreenshots.hasFullAccess)
                SetupStatus(title: "Coax keyboard", on: KeyboardCheck.isAdded)
            }
            VStack(alignment: .leading, spacing: 12) {
                DoneMove(number: 1, text: "Screenshot the chat")
                DoneMove(number: 2, text: "Tap the message box, then switch to Coax with 🌐")
                DoneMove(number: 3, text: "Tap 1, 2 or 3")
            }
            #if DEBUG
            // Voice profile is a Sprint 3 preview: test builds only for now.
            Button { showVoice = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(Color.coax)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make it sound like you").font(.headline).foregroundStyle(.primary)
                        Text("Optional · about 20 seconds").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color.coaxSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("voiceQuizCard")
            #endif
        } bottom: {
            Button("Start using Coax") { finish() }
                .buttonStyle(PrimaryButton())
        }
        .sheet(isPresented: $showVoice) { VoiceProfileView() }
    }

    // MARK: Age screens (only when Apple's age range says so)

    private var checkingAge: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking your age range").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var turnedAway: some View {
        SetupPage(step: 0, onBack: nil) {
            ScreenTitle(title: "Coax is for people 16 and older",
                        subtitle: "Thanks for checking it out. Coax will be here when you're 16.")
        } bottom: {
            #if DEBUG
            // Test builds only, so you can try the other paths without deleting the app.
            Button("Start over (test builds only)") {
                AgeSettings.reset()
                go(.tryIt)
            }
            .buttonStyle(SecondaryButton())
            #endif
        }
        .accessibilityIdentifier("turnedAway")
    }

    private var parentOK: some View {
        SetupPage(step: 0, onBack: nil) {
            ScreenTitle(title: "Ask a parent or guardian",
                        subtitle: "You're 16 or 17, so a parent or guardian needs to say it's OK to use Coax. Your replies stay friendly: nothing sexual, no alcohol or drugs.")
            Text("If your iPhone is part of Family Sharing, iOS may also ask them first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } bottom: {
            Button("My parent or guardian said OK") {
                AgeSettings.parentOK = Date()
                go(.tryIt)
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func finish() {
        AgeSettings.onboarded = true
        onFinish()
    }
}

// MARK: - 1. Try it: welcome and a real reply in one screen

private struct TryItStep: View {
    var onNext: () -> Void
    @StateObject private var model = ReplyFlowModel()
    @State private var picked: ReplySuggestion?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Wordmark()
                    ScreenTitle(title: "Know what to text back.",
                                subtitle: "Coax reads the chat and writes three replies that sound like you.")
                    VStack(spacing: 4) {
                        ForEach(ReplyFlowModel.exampleChat.suffix(3)) { ChatBubble(message: $0) }
                    }
                    messageBox
                    replies
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            VStack(spacing: 6) {
                Button("Set it up · 1 minute") { onNext() }
                    .buttonStyle(PrimaryButton())
                Text("Free to start · No account · No card")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .task {
            if model.replies.isEmpty { await model.tryExample() }
        }
    }

    /// The message box, with the tapped reply typed in.
    private var messageBox: some View {
        HStack {
            Text(picked?.text ?? "iMessage")
                .foregroundStyle(picked == nil ? .secondary : .primary)
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Capsule().strokeBorder(Color(.separator)))
        .animation(.default, value: picked)
    }

    /// Drawn like the Coax keyboard: 1·2·3 cards, then mood tags.
    @ViewBuilder private var replies: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.phase {
            case .failed(let message):
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await model.tryExample() } }
                    .buttonStyle(SecondaryButton())
            case .done:
                Text("Tap one to put it in the message box")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, reply in
                    CoaxReplyCard(number: index + 1, reply: reply, copied: picked == reply) {
                        picked = reply
                    }
                }
                MoodTagRow(model: model, background: Color(.systemBackground)) { picked = nil }
            default:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing replies…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Pictures

/// Coax's page in Settings, where Open Settings lands, with the taps numbered.
private struct SettingsPicture: View {
    /// Only some photos were allowed: fix it on the same page.
    var fixPhotos: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings › Coax")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                if fixPhotos {
                    row(nil, "Photos", detail: "Full Access")
                    Divider().padding(.leading, 12)
                }
                row(1, "Keyboards", detail: "›")
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Then")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row(2, "Coax", toggle: true)
                Divider().padding(.leading, 12)
                row(3, "Allow Full Access", toggle: true)
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((fixPhotos ? "In Settings, set Photos to Full Access. " : "In Settings, ")
                            + "tap Keyboards, turn on Coax, then turn on Allow Full Access.")
    }

    private func row(_ n: Int?, _ title: String, detail: String? = nil, toggle: Bool = false) -> some View {
        HStack {
            if let n {
                Text("\(n)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.coax, in: Circle())
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            Text(title)
            Spacer()
            if toggle {
                Toggle("", isOn: .constant(true)).labelsHidden().allowsHitTesting(false).tint(.green)
            } else if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A screenshot turning into replies in the keyboard.
private struct ScreenshotPicture: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<6) { i in
                    Capsule()
                        .fill(i % 3 == 1 ? Color.coax : Color(.systemGray4))
                        .frame(width: i % 3 == 1 ? 34 : 44, height: 7)
                        .frame(maxWidth: .infinity, alignment: i % 3 == 1 ? .trailing : .leading)
                }
            }
            .padding(8)
            .frame(width: 72, height: 130)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 2))
            Image(systemName: "arrow.right").foregroundStyle(Color.coax)
            VStack(spacing: 5) {
                Capsule().fill(Color.coax).frame(height: 10)
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(Color(.systemBackground)).frame(height: 16)
                }
            }
            .padding(8)
            .frame(width: 104)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }
}

private struct Promise: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.coaxDone)
                .frame(width: 22)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - Page frame

/// A setup screen: top bar, scrolling content, one main button at the bottom.
/// What happened after tapping Agree on the Photos screen.
private struct PhotosResult: View {
    var on: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(on ? Color.coaxDone : Color.orange)
                .accessibilityHidden(true)
            Text(on ? "Photos is on" : "Photos is still off. You can turn it on on the next screen.")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((on ? Color.coaxDone : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SetupStatus: View {
    var title: String
    var on: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if on {
                Label("On", systemImage: "checkmark").foregroundStyle(Color.coaxDone)
            } else {
                Text("Off · turn on in Settings").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

private struct DoneMove: View {
    var number: Int
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.coax, in: Circle())
            Text(text).font(.body)
        }
    }
}

private struct SetupPage<Content: View, Bottom: View>: View {
    var step: Int
    var onBack: (() -> Void)?
    var skipTitle: String? = nil
    var onSkip: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                SetupBar(step: step, total: 2, onBack: onBack, skipTitle: skipTitle, onSkip: onSkip)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(.horizontal, 20)
                    .padding(.top, step > 0 ? 12 : 48)
                    .padding(.bottom, 16)
            }
            bottom
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }
}

#Preview {
    OnboardingView {}
}
