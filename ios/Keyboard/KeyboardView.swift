import SwiftUI

struct KeyboardActions {
    var getRepliesFromScreenshots: () -> Void
    var getReplies: () -> Void
    var insert: (ReplySuggestion) -> Void
    var type: (String) -> Void
    var deleteBackward: () -> Void
    var nextKeyboard: () -> Void
}

/// Option 1, "one step at a time" (Vanessa, Nov 6): every screen shows one
/// obvious next step and every control has words on it.
/// - Before replies: one big "Scan my last screenshot" button, "Long chat?
///   Scan the last 1 2 3", and a "paste text you copied" link.
/// - Replies: tapping a reply only picks it; Insert types it in, so a wrong tap
///   costs nothing. After Insert a note says it's in your message; picking
///   another reply and tapping Swap replaces it.
/// - A slim header holds the globe (Apple's keyboard, for edits) and "Scan again".
/// Coax's own letter keys only show without Full Access, so typing still works
/// then (App Review rule 4.4.1); replies need it, because without it iOS gives
/// keyboards no clipboard and no internet.
struct KeyboardView: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    var body: some View {
        VStack(spacing: 6) {
            header
            Group {
                switch state.panel {
                case .keys:
                    LetterKeys(state: state, actions: actions)
                case .replies:
                    RepliesPanel(model: model, state: state, actions: actions,
                                 scan: { start(actions.getRepliesFromScreenshots) },
                                 paste: { start(actions.getReplies) })
                case .review:
                    ChatReview(model: model) {
                        state.insertedID = nil
                        state.panel = .replies
                    }
                case .fullAccessHelp:
                    FullAccessHelp()
                case .say:
                    SayEditor(model: model, state: state, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Globe on the left (always: it's how you edit a reply on Apple's
    /// keyboard), what this screen is for in the middle, one action on the right.
    private var header: some View {
        HStack(spacing: 8) {
            Button(action: actions.nextKeyboard) {
                Label("Keyboard", systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color(.systemBackground), in: Capsule())
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next keyboard")
            .accessibilityHint("Switches to your usual keyboard, for edits")

            Text(headerTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            headerAction
        }
        .padding(.horizontal, 2)
    }

    private var headerTitle: String {
        switch state.panel {
        case .replies:
            guard case .done = model.phase, !model.replies.isEmpty else { return "" }
            return state.insertedID == nil ? "Pick a reply" : "Changed your mind?"
        case .say:
            return "Tell Coax what to say"
        case .keys, .review, .fullAccessHelp:
            return ""
        }
    }

    @ViewBuilder private var headerAction: some View {
        switch state.panel {
        case .keys:
            HeaderLink(title: "Get replies", systemImage: "sparkles") { state.panel = .fullAccessHelp }
        case .fullAccessHelp:
            HeaderLink(title: "Type", systemImage: "keyboard") { state.panel = .keys }
        case .replies:
            if showsCheckChat {
                HeaderLink(title: "Check chat", systemImage: nil) { state.panel = .review }
                    .accessibilityLabel(ReadSummaryButton.summary(model) ?? "Check chat")
                    .accessibilityHint("Shows who said what, so you can fix it")
            }
            if showsScanAgain {
                HeaderLink(title: "Scan again", systemImage: "arrow.clockwise") {
                    start(actions.getRepliesFromScreenshots)
                }
                .accessibilityLabel(state.screenshotCount == 1 ? "Scan my last screenshot again"
                                                               : "Scan my last \(state.screenshotCount) screenshots again")
            }
        case .say:
            HeaderLink(title: model.hasIntent ? "Remove" : "Cancel",
                       systemImage: model.hasIntent ? "xmark" : "chevron.left") {
                state.panel = .replies
                if model.hasIntent {
                    state.insertedID = nil
                    state.selectedID = nil
                    Task { await model.clearIntent() }
                }
            }
            .accessibilityLabel(model.hasIntent ? "Remove your line" : "Cancel, back to replies")
        case .review:
            EmptyView()
        }
    }

    /// "Check chat" (who said what) lives in the header, so the replies get the room.
    private var showsCheckChat: Bool {
        guard case .done = model.phase else { return false }
        return ReadSummaryButton.summary(model) != nil
    }

    private var showsScanAgain: Bool {
        switch model.phase {
        case .done, .failed: return true
        case .waiting, .reading, .generating: return false
        }
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

private struct HeaderLink: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(Color.coax)
            .frame(minHeight: 28)
            // Easier to hit than it looks (Apple's minimum is 44 points).
            .padding(.vertical, 8).contentShape(Rectangle()).padding(.vertical, -8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Replies

private struct RepliesPanel: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions
    var scan: () -> Void
    var paste: () -> Void

    var body: some View {
        switch model.phase {
        case .waiting:
            StartScreen(state: state, scan: scan, paste: paste)
        case .reading:
            Working(previews: model.previews,
                    text: state.autoRead ? "Reading your new screenshot…" : "Reading the chat…")
        case .generating:
            Working(previews: model.previews, text: "Writing replies…")
        case .failed(let reason):
            VStack(spacing: 10) {
                Hint(systemImage: "exclamationmark.triangle", text: reason)
                Button("Or paste text you copied", action: paste)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.coax)
            }
        case .done:
            let selected = selectedIndex
            let alreadyIn = selected.map { state.insertedID == model.replies[$0].id } ?? false
            VStack(spacing: 6) {
                if alreadyIn, let selected {
                    InsertedNote(number: selected + 1)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, reply in
                            ReplyCard(number: index + 1, reply: reply,
                                      selected: index == selected && !alreadyIn,
                                      inserted: state.insertedID == reply.id) {
                                state.selectedID = reply.id
                            }
                        }
                        if alreadyIn {
                            Text("Tap another reply to swap it in")
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
                if let selected, !alreadyIn {
                    InsertButton(number: selected + 1, swapping: state.insertedID != nil) {
                        actions.insert(model.replies[selected])
                    }
                }
                MoodTagRow(model: model, background: Color(.systemBackground), tellCoax: true,
                           onTellCoax: {
                               state.sayDraft = model.intent
                               state.shifted = state.sayDraft.isEmpty
                               state.showingSymbols = false
                               state.panel = .say
                           }) {
                    state.insertedID = nil
                    state.selectedID = nil
                }
            }
        }
    }

    /// The picked reply; reply 1 until another is tapped.
    private var selectedIndex: Int? {
        guard !model.replies.isEmpty else { return nil }
        return model.replies.firstIndex { $0.id == state.selectedID } ?? 0
    }
}

/// Before any replies: one big button, the screenshot count in plain words,
/// and paste as a small backup.
private struct StartScreen: View {
    @ObservedObject var state: KeyboardState
    var scan: () -> Void
    var paste: () -> Void
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text("Screenshot the chat, or scan the last one")
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            Button(action: scan) {
                Label(state.screenshotCount == 1 ? "Scan my last screenshot" : "Scan my last \(state.screenshotCount) screenshots",
                      systemImage: "camera.viewfinder")
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.coax, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Reads it on your iPhone and writes 3 replies")
            HStack(spacing: 6) {
                Text("Long chat? Scan the last").font(.caption).foregroundStyle(.secondary)
                ForEach(1...3, id: \.self) { n in
                    Button("\(n)") { state.screenshotCount = n }
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 24)
                        .background(n == state.screenshotCount ? Color.coax : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(n == state.screenshotCount ? Color.white : Color.primary)
                        .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan the last \(n) screenshot\(n == 1 ? "" : "s")")
                        .accessibilityAddTraits(n == state.screenshotCount ? .isSelected : [])
                }
            }
            Button("Or paste text you copied", action: paste)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.coax)
                .accessibilityHint("Writes replies to a message you copied")
            if state.watching {
                HStack(spacing: 6) {
                    Circle().fill(Color.coax).frame(width: 6, height: 6).opacity(dim ? 0.25 : 1)
                    Text("Ready for your next screenshot").font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 2)
    }
}

/// Shown after Insert, so it's clear the reply went in and what to do next.
private struct InsertedNote: View {
    var number: Int

    var body: some View {
        Label("Reply \(number) is in your message. Send it, or tap Keyboard to edit it with your usual keys.", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 8)
            .background(Color.coax.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 2)
    }
}

/// Puts the picked reply in the message box. Nothing is typed until this is tapped.
private struct InsertButton: View {
    var number: Int
    var swapping: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(swapping ? "Swap in reply \(number)" : "Insert reply \(number)", systemImage: "arrow.up.message")
                .font(.callout.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.coax, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .accessibilityHint(swapping ? "Replaces the reply already in your message" : "Types it into the message box")
    }
}

/// A numbered reply with its mood. Blue outline when picked, green check once inserted.
private struct ReplyCard: View {
    var number: Int
    var reply: ReplySuggestion
    var selected: Bool
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.coax : (inserted ? Color.coaxDone : Color.clear), lineWidth: selected ? 2 : 1.5))
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(number). " + (reply.label.map { "\($0): \(reply.text)" } ?? reply.text))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(inserted ? "In your message" : "Picks this reply. Then tap Insert")
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

/// "Type what to say": type what the reply should say on Coax's letter keys, then Get replies.
/// Return also writes. Nothing typed here goes into the chat.
private struct SayEditor: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var state: KeyboardState
    var actions: KeyboardActions

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Group {
                    if state.sayDraft.isEmpty {
                        Text("e.g. say I'm busy, but free Sunday")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(state.sayDraft + "|")
                            .foregroundStyle(.primary)
                    }
                }
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(Text(state.sayDraft.isEmpty ? "What should the reply say? Empty" : state.sayDraft))

                Button(action: write) {
                    Text("Get replies")
                        .font(.callout.weight(.bold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(Color.coax, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.45 : 1)
                .accessibilityHint("Gets replies that say this")
            }
            LetterKeys(state: state, actions: KeyboardActions(
                getRepliesFromScreenshots: actions.getRepliesFromScreenshots,
                getReplies: actions.getReplies,
                insert: actions.insert,
                type: type,
                deleteBackward: { if !state.sayDraft.isEmpty { state.sayDraft.removeLast() }; autoCapital() },
                nextKeyboard: actions.nextKeyboard))
        }
    }

    private var trimmed: String { state.sayDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func type(_ text: String) {
        if text == "\n" { write(); return }
        guard state.sayDraft.count < ReplyFlowModel.maxIntent else { return }
        state.sayDraft += text
        autoCapital()
    }

    private func autoCapital() {
        let shift = Typing.startsSentence(state.sayDraft)
        if state.shifted != shift { state.shifted = shift }
    }

    private func write() {
        guard !trimmed.isEmpty else { return }
        let line = trimmed
        state.insertedID = nil
        state.selectedID = nil
        state.panel = .replies
        Task { await model.say(line) }
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
