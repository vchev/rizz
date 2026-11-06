import SwiftUI

struct KeyboardActions {
    var getRepliesFromScreenshots: () -> Void
    var getReplies: () -> Void
    var insert: (ReplySuggestion) -> Void
    var type: (String) -> Void
    var deleteBackward: () -> Void
    var nextKeyboard: () -> Void
}

/// Direction A (Nov 5, revised Nov 6): the keyboard opens on your replies. One
/// bar on top ([Type] [Use my last screenshot] [shots count] [clipboard]
/// [globe]), then three numbered reply cards with their mood, then the mood
/// tags. Tapping a reply types it in and Coax stays open: tapping another swaps
/// it. Coax's own letter keys sit behind Type: typing works without Full Access (App Review rule
/// 4.4.1); replies need it, because without it iOS gives keyboards no
/// clipboard and no internet.
struct KeyboardView: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    var body: some View {
        VStack(spacing: 6) {
            topBar
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

    private var topBar: some View {
        HStack(spacing: 6) {
            // Type opens Coax's letter keys; on the keys it turns into a way back to replies.
            Button {
                state.panel = state.panel == .keys ? (state.hasFullAccess ? .replies : .fullAccessHelp) : .keys
            } label: {
                Group {
                    if state.panel == .keys {
                        Image(systemName: "text.bubble.fill")
                    } else {
                        Text("Type")
                    }
                }
                .font(.caption.weight(.bold))
                .frame(width: 48, height: 34)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.panel == .keys ? "Back to replies" : "Type with letters")

            ReplyBarButton(title: state.screenshotCount == 1 ? "Use my last screenshot" : "Use my last \(state.screenshotCount)",
                           systemImage: "photo.on.rectangle", prominent: true) {
                start(actions.getRepliesFromScreenshots)
            }
            .disabled(model.isBusy)
            .accessibilityLabel(state.screenshotCount == 1 ? "Reply to my last screenshot"
                                                           : "Reply to my last \(state.screenshotCount) screenshots")
            .accessibilityHint("Reads it on your iPhone. Or take a new screenshot and Coax reads it by itself")
            ShotCountButton(count: $state.screenshotCount)
                .disabled(model.isBusy)
            // Backup for when a screenshot can't be read: replies to whatever was copied.
            Button {
                start(actions.getReplies)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.footnote)
                    .frame(width: 34, height: 34)
                    .background(Color(.systemBackground), in: Circle())
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Get replies to what I copied")
            if state.showsGlobe {
                Button(action: actions.nextKeyboard) {
                    Image(systemName: "globe")
                        .font(.footnote)
                        .frame(width: 34, height: 34)
                        .background(Color(.systemBackground), in: Circle())
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next keyboard")
            }
        }
        .padding(.horizontal, 2)
    }

    private func start(_ action: () -> Void) {
        if state.hasFullAccess {
            state.panel = .replies
            action()
        } else {
            state.panel = .fullAccessHelp
        }
    }
}

/// How many recent screenshots to read (1, 2 or 3). One small button that
/// cycles, so the 1·2·3 on the reply cards stays the only big set of numbers.
private struct ShotCountButton: View {
    @Binding var count: Int

    var body: some View {
        Button {
            count = count % 3 + 1
        } label: {
            HStack(spacing: 1) {
                Image(systemName: "photo.stack").imageScale(.small)
                Text("\(count)")
            }
            .font(.caption.weight(.bold))
            .frame(width: 40, height: 34)
            .background(Color(.systemBackground), in: Capsule())
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read \(count) screenshot\(count == 1 ? "" : "s")")
        .accessibilityHint("Tap to change how many recent screenshots Coax reads")
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
            Waiting(watching: state.watching)
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
                        ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, reply in
                            ReplyCard(number: index + 1, reply: reply, inserted: state.insertedID == reply.id) {
                                actions.insert(reply)
                            }
                        }
                        if state.insertedID != nil {
                            Text("In your message. Tap another reply to swap it.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if model.service.isSample {
                            Text("Sample replies until the reply engine is connected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                MoodTagRow(model: model, background: Color(.systemBackground)) {
                    state.insertedID = nil
                }
            }
        }
    }
}

/// A numbered reply with its mood, as in the direction A mockup.
private struct ReplyCard: View {
    var number: Int
    var reply: ReplySuggestion
    var inserted: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if inserted {
                        Image(systemName: "checkmark").font(.caption.weight(.bold))
                    } else {
                        Text("\(number)").font(.footnote.weight(.bold))
                    }
                }
                .frame(width: 24, height: 24)
                .background(inserted ? Color.coaxDone : Color.coax.opacity(0.14), in: Circle())
                .foregroundStyle(inserted ? Color.white : Color.coax)
                Text(reply.text)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let label = reply.label, !label.isEmpty {
                    Text(label.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(inserted ? Color.coaxDone : Color.clear, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(number). " + (reply.label.map { "\($0): \(reply.text)" } ?? reply.text))
        .accessibilityHint(inserted ? "Already in the message box" : "Types this reply into the message box, replacing one picked before")
    }
}

/// Before the first screenshot: what to do, and that Coax is watching.
private struct Waiting: View {
    var watching: Bool
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").font(.title).foregroundStyle(Color.coax)
            Text("Screenshot the chat. Your replies show up here.")
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            if watching {
                HStack(spacing: 6) {
                    Circle().fill(Color.coax).frame(width: 6, height: 6).opacity(dim ? 0.25 : 1)
                    Text("Ready for your next screenshot").font(.caption).foregroundStyle(.secondary)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true }
                }
            } else {
                Text("Or copy their message and tap the clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
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
