import SwiftUI

struct KeyboardActions {
    var getRepliesFromScreenshots: () -> Void
    var getReplies: () -> Void
    var insert: (ReplySuggestion) -> Void
    var type: (String) -> Void
    var deleteBackward: () -> Void
    var nextKeyboard: () -> Void
}

/// A normal typing keyboard with a reply bar on top.
/// Typing works without Full Access (App Review rule 4.4.1); replies need it,
/// because without it iOS gives keyboards no clipboard and no internet.
struct KeyboardView: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    var body: some View {
        VStack(spacing: 6) {
            topBar
            if state.panel == .keys && state.watching && !model.isBusy {
                WatchingLine()
            }
            Group {
                switch state.panel {
                case .keys:
                    LetterKeys(state: state, actions: actions)
                case .replies:
                    RepliesPanel(model: model, state: state, actions: actions)
                case .review:
                    ChatReview(model: model) {
                        state.insertedID = nil
                        state.panel = .replies
                    }
                case .fullAccessHelp:
                    FullAccessHelp()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Same bar on every screen: [keyboard] [Last N screenshots] [1 2 3] [clipboard].
    /// The keyboard button sits on the left, in a dark circle, whenever the keys are hidden.
    private var topBar: some View {
        HStack(spacing: 6) {
            if state.panel != .keys {
                Button {
                    state.panel = .keys
                } label: {
                    Image(systemName: "keyboard")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 38, height: 34)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to typing")
            }
            ReplyBarButton(title: state.screenshotCount == 1 ? "Last screenshot" : "Last \(state.screenshotCount)",
                           systemImage: "camera.viewfinder", prominent: true) {
                start(actions.getRepliesFromScreenshots)
            }
            .disabled(model.isBusy)
            .accessibilityLabel(state.screenshotCount == 1 ? "Reply to my last screenshot"
                                                           : "Reply to my last \(state.screenshotCount) screenshots")
            ScreenshotCountPicker(count: $state.screenshotCount)
                .disabled(model.isBusy)
            // Backup for when a screenshot can't be read: replies to whatever was copied.
            Button {
                start(actions.getReplies)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 38, height: 34)
                    .background(Color(.systemBackground), in: Capsule())
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Get replies to what I copied")
        }
        .padding(.horizontal, 2)
    }

    private func start(_ action: () -> Void) {
        if state.hasFullAccess {
            state.panel = .replies
            action()
        } else {
            state.panel = state.panel == .fullAccessHelp ? .keys : .fullAccessHelp
        }
    }
}

/// How many recent screenshots to read: 1, 2 or 3, all visible at once.
private struct ScreenshotCountPicker: View {
    @Binding var count: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...3, id: \.self) { n in
                Button {
                    count = n
                } label: {
                    Text("\(n)")
                        .font(.footnote.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(n == count ? Color.coax : Color.clear, in: Circle())
                        .foregroundStyle(n == count ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read \(n) screenshot\(n == 1 ? "" : "s")")
                .accessibilityAddTraits(n == count ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(.systemBackground), in: Capsule())
    }
}

/// A quiet line under the bar: Coax is ready for the next screenshot.
private struct WatchingLine: View {
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.coax)
                .frame(width: 6, height: 6)
                .opacity(dim ? 0.25 : 1)
            Text("Take a screenshot and I'll read it right away")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReplyBarButton: View {
    var title: String
    var systemImage: String
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(prominent ? Color.coax : Color(.systemBackground), in: Capsule())
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Replies

private struct RepliesPanel: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    var body: some View {
        switch model.phase {
        case .waiting:
            Hint(systemImage: "camera.viewfinder",
                 text: "Take a screenshot of the chat and I'll read it. Pick 1, 2 or 3 to read more of the chat, or copy their message and tap the clipboard.")
        case .reading:
            Working(previews: model.previews,
                    text: state.autoRead ? "Reading your new screenshot…" : "Reading the chat…")
        case .generating:
            Working(previews: model.previews, text: "Writing replies…")
        case .failed(let reason):
            Hint(systemImage: "exclamationmark.triangle", text: reason)
        case .done:
            VStack(spacing: 6) {
                ScrollView {
                    VStack(spacing: 6) {
                        ReadSummaryButton(model: model) { state.panel = .review }
                        ForEach(model.replies) { reply in
                            ReplyCard(reply: reply, inserted: state.insertedID == reply.id) {
                                actions.insert(reply)
                            }
                        }
                        if model.service.isSample {
                            Text("Sample replies until the reply engine is connected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                HStack(spacing: 6) {
                    ForEach(ReplyTone.allCases) { tone in
                        Button {
                            state.insertedID = nil
                            Task { await model.generate(tone: tone) }
                        } label: {
                            Text(tone.label)
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Color(.systemBackground), in: Capsule())
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ReplyCard: View {
    var reply: ReplySuggestion
    var inserted: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = reply.label, !label.isEmpty {
                        Text(label.uppercased())
                            .font(.caption2.weight(.bold))
                            .kerning(0.4)
                            .foregroundStyle(inserted ? Color.coaxDone : Color.coax)
                    }
                    Text(reply.text)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: inserted ? "checkmark.circle.fill" : "arrow.up.circle")
                    .foregroundStyle(inserted ? Color.coaxDone : Color.coax)
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inserted ? Color.coaxDone : Color.clear, lineWidth: 1.5))
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reply.label.map { "\($0): \(reply.text)" } ?? reply.text)
        .accessibilityHint("Types this reply into the message box")
    }
}

private struct Hint: View {
    var systemImage: String
    var text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }
}

/// Shows the screenshots being read, small, so people know what Coax is looking at.
private struct Working: View {
    var previews: [UIImage]
    var text: String

    var body: some View {
        VStack(spacing: 10) {
            if !previews.isEmpty {
                HStack(spacing: 8) {
                    ForEach(previews.indices, id: \.self) { i in
                        Image(uiImage: previews[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.coax, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                ProgressView()
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FullAccessHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To get replies, turn on Full Access")
                .font(.callout.weight(.semibold))
            Text("Open the Settings app › General › Keyboard › Keyboards › Coax, and turn on Allow Full Access.")
                .font(.footnote)
            Text("iPhone needs this before a keyboard can read what you copied or fetch replies. Typing works either way, and we never record what you type.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Typing keys

private struct LetterKeys: View {
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    private static let letters = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private static let symbols = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    var body: some View {
        let rows = state.showingSymbols ? Self.symbols : Self.letters
        VStack(spacing: 8) {
            row(rows[0])
            row(rows[1])
                .padding(.horizontal, state.showingSymbols ? 0 : 16)
            HStack(spacing: 5) {
                if state.showingSymbols {
                    Spacer(minLength: 0)
                } else {
                    SystemKey(systemImage: state.shifted ? "shift.fill" : "shift") {
                        state.shifted.toggle()
                    }
                    .frame(width: 44)
                }
                row(rows[2])
                SystemKey(systemImage: "delete.left", repeats: true, action: actions.deleteBackward)
                    .frame(width: 44)
            }
            HStack(spacing: 5) {
                SystemKey(text: state.showingSymbols ? "ABC" : "123") {
                    state.showingSymbols.toggle()
                }
                .frame(width: 50)
                if state.showsGlobe {
                    SystemKey(systemImage: "globe", action: actions.nextKeyboard)
                        .frame(width: 44)
                }
                CharacterKey(label: "space") { actions.type(" ") }
                SystemKey(text: "return") { actions.type("\n") }
                    .frame(width: 80)
            }
        }
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                let shown = state.shifted && !state.showingSymbols ? key.uppercased() : key
                CharacterKey(label: shown) {
                    actions.type(shown)
                    if state.shifted { state.shifted = false }
                }
            }
        }
    }
}

/// A light tap on every key, like Apple's keyboard with Keyboard Haptics on.
/// iOS only lets a keyboard vibrate when it has Full Access; without it this does nothing.
@MainActor
enum KeyHaptics {
    private static let generator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    static func tap() {
        generator.impactOccurred()
        generator.prepare()   // keeps the next tap instant
    }
}

/// Fires on touch-down, like Apple's keys, instead of on lift. Optionally
/// repeats while held (the delete key).
private struct TouchDownKey<Label: View>: View {
    var repeats = false
    var action: () -> Void
    @ViewBuilder var label: (_ pressed: Bool) -> Label
    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        UIDevice.current.playInputClick()
                        KeyHaptics.tap()
                        action()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            while !Task.isCancelled && pressed {
                action()
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
    }
}

private struct CharacterKey: View {
    var label: String
    var action: () -> Void

    var body: some View {
        TouchDownKey(action: action) { pressed in
            Text(label)
                .font(label.count == 1 ? .title3 : .callout)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(pressed && label.count > 1 ? Color(.systemGray4) : Color(.systemBackground),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.primary)
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
                .overlay(alignment: .bottom) {
                    // The pop-up letter above the key while it's held.
                    if pressed && label.count == 1 {
                        Text(label)
                            .font(.system(size: 30))
                            .frame(width: 46, height: 52)
                            .background(Color(.systemBackground),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .offset(y: -46)
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(pressed ? 1 : 0)
        }
        .accessibilityLabel(label)
    }
}

private struct SystemKey: View {
    var systemImage: String? = nil
    var text: String? = nil
    var repeats = false
    var action: () -> Void

    var body: some View {
        TouchDownKey(repeats: repeats, action: action) { pressed in
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let text {
                    Text(text).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(pressed ? Color(.systemBackground) : Color(.systemGray3),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Color.primary)
            .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
        }
        .accessibilityLabel(text ?? systemImage ?? "")
    }
}
