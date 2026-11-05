import SwiftUI
import UIKit

/// First-run setup: welcome, a real reply in under a minute,
/// then the one-time keyboard setup. Shown until it's finished once.
///
/// Order follows the onboarding design doc, with the practice reply moved up
/// so people see Coax work before any setup.
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Step: Equatable {
        case welcome, checkingAge, turnedAway, parentOK
        case tryIt, fullAccess, keyboard, photos
    }

    @State private var step: Step
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
        case .teen, .adult: return .tryIt
        case nil: return .welcome
        }
    }

    var body: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .checkingAge: checkingAge
            case .turnedAway: turnedAway
            case .parentOK: parentOK
            case .tryIt: TryItStep { go(.fullAccess) }
            case .fullAccess: fullAccess
            case .keyboard: keyboard
            case .photos: photos
            }
        }
        .animation(.default, value: step)
        .tint(Color.accentColor)
    }

    private func go(_ next: Step) { withAnimation { step = next } }

    // MARK: Age

    /// No age screen (decided Nov 4): the App Store's 16+ rating gates downloads.
    /// Apple's age range, once switched on (paid developer account), quietly sets
    /// teen mode or turns away under-16s, with a time limit so it can never hang.
    /// No answer = carry on to the sample replies.
    private func checkAge() {
        if uiTesting {
            if let group = Self.testAppleAge { set(group) } else { go(.tryIt) }
            return
        }
        guard AgeCheck.isEnabled else { go(.tryIt); return }
        go(.checkingAge)
        Task {
            if let group = await AgeCheck.askApple(timeout: 3) {
                AgeSettings.source = "apple"
                set(group)
            } else {
                go(.tryIt)
            }
        }
    }

    private func set(_ group: AgeGroup) {
        AgeSettings.ageGroup = group
        switch group {
        case .under16: go(.turnedAway)
        case .teen: go(.parentOK)
        case .adult: go(.tryIt)
        }
    }

    // MARK: Screens

    private var welcome: some View {
        StepPage(icon: "bubble.left.and.text.bubble.right.fill",
                 title: "Replies that sound like you, one tap away",
                 subtitle: "Free to start. No card, no account.") {
            Button("Get started") { checkAge() }
                .buttonStyle(PrimaryButton())
        }
    }

    private var checkingAge: some View {
        StepPage(icon: "person.badge.shield.checkmark",
                 title: "Checking your age range",
                 subtitle: "iPhone shares only a range, never your birthday.") {
            ProgressView()
        }
    }

    private var turnedAway: some View {
        StepPage(icon: "hand.raised",
                 title: "Coax is for people 16 and older",
                 subtitle: "Thanks for checking it out. Coax will be here when you're 16.") {
            #if DEBUG
            // Test builds only, so you can try the other paths without deleting the app.
            Button("Start over (test builds only)") {
                AgeSettings.reset()
                go(.welcome)
            }
            .buttonStyle(SecondaryButton())
            #endif
        }
        .accessibilityIdentifier("turnedAway")
    }

    private var parentOK: some View {
        StepPage(icon: "figure.and.child.holdinghands",
                 title: "Ask a parent or guardian",
                 subtitle: "You're 16 or 17, so a parent or guardian needs to say it's OK to use Coax. Your replies stay friendly: nothing sexual, no alcohol or drugs.") {
            VStack(spacing: 12) {
                Button("My parent or guardian said OK") {
                    AgeSettings.parentOK = Date()
                    go(.tryIt)
                }
                .buttonStyle(PrimaryButton())
                Text("If your iPhone is part of Family Sharing, iOS may also ask them first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var fullAccess: some View {
        StepPage(icon: "lock.shield",
                 title: "Your replies wait in the Coax keyboard",
                 subtitle: "iPhone will show a scary warning when you turn on Full Access. Here's what Coax actually does.") {
            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "network", text: "Full Access lets Coax bring replies into the keyboard and reach the internet.")
                Bullet(icon: "keyboard", text: "Coax never records or sends what you type on its keys.")
                Bullet(icon: "iphone", text: "Screenshots are read on your phone. Only the chat text is sent, and it isn't kept.")
                Button("Next") { go(KeyboardCheck.isAdded ? .photos : .keyboard) }
                    .buttonStyle(PrimaryButton())
                    .padding(.top, 8)
            }
        }
    }

    private var keyboard: some View {
        StepPage(icon: "keyboard.badge.ellipsis",
                 title: "Turn on the Coax keyboard",
                 subtitle: "One time. Coax moves on by itself when you come back.") {
            VStack(alignment: .leading, spacing: 12) {
                NumberedLine(number: 1, text: "Tap Open Settings, then Keyboards.")
                NumberedLine(number: 2, text: "Turn on Coax.")
                NumberedLine(number: 3, text: "Turn on Allow Full Access, then tap Allow.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButton())
                .padding(.top, 8)
                Button("Skip for now") { go(.photos) }
                    .buttonStyle(SecondaryButton())
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, KeyboardCheck.isAdded { go(.photos) }
        }
    }

    private var photos: some View {
        StepPage(icon: "photo.on.rectangle",
                 title: "Let Coax read your screenshots",
                 subtitle: "Take a screenshot of a chat while the Coax keyboard is open, and your replies appear. Screenshots are read on your phone and never uploaded.") {
            VStack(spacing: 12) {
                Button("Allow Photos") {
                    Task {
                        if !uiTesting { _ = await RecentScreenshots.requestAccess() }
                        finish()
                    }
                }
                .buttonStyle(PrimaryButton())
                Button("Not now") { finish() }
                    .buttonStyle(SecondaryButton())
            }
        }
    }

    private func finish() {
        AgeSettings.onboarded = true
        onFinish()
    }
}

// MARK: - A real reply in the first minute

private struct TryItStep: View {
    var onNext: () -> Void
    @StateObject private var model = ReplyFlowModel()
    @State private var copiedID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("See it work")
                    .font(.largeTitle.bold())
                Text("Here's a chat with a match. Coax reads it and writes 3 replies in your style.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(ReplyFlowModel.exampleChat) { message in
                        Bubble(message: message)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                replies

                Button("Next") { onNext() }
                    .buttonStyle(PrimaryButton())
                    .disabled(model.isBusy)
            }
            .padding(24)
        }
        .task {
            if model.replies.isEmpty { await model.tryExample() }
        }
    }

    @ViewBuilder private var replies: some View {
        switch model.phase {
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await model.tryExample() } }
                    .buttonStyle(SecondaryButton())
            }
        case .done:
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap one to copy it").font(.headline)
                ForEach(model.replies) { reply in
                    Button {
                        UIPasteboard.general.string = reply.text
                        copiedID = reply.id
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reply.text).foregroundStyle(.primary)
                                if let label = reply.label {
                                    Text(label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if copiedID == reply.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        default:
            HStack(spacing: 10) {
                ProgressView()
                Text("Writing replies…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}

private struct Bubble: View {
    var message: ChatMessage

    var body: some View {
        let mine = message.speaker == .you
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(mine ? .white : .primary)
                .background(mine ? Color.accentColor : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !mine { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Building blocks

private struct StepPage<Content: View>: View {
    var icon: String
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 48)
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                content
                    .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Bullet: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
    }
}

private struct NumberedLine: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.footnote.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}

private struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview {
    OnboardingView {}
}
