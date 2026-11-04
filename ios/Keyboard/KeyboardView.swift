import SwiftUI

struct KeyboardActions {
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
            Group {
                switch state.panel {
                case .keys:
                    LetterKeys(state: state, actions: actions)
                case .replies:
                    RepliesPanel(model: model, state: state, actions: actions)
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
        HStack(spacing: 8) {
            Button {
                if state.hasFullAccess {
                    state.panel = .replies
                    actions.getReplies()
                } else {
                    state.panel = state.panel == .fullAccessHelp ? .keys : .fullAccessHelp
                }
            } label: {
                Label(model.phase == .done ? "New replies from what I copied" : "Get replies from what I copied",
                      systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            if state.panel != .keys {
                Button {
                    state.panel = .keys
                } label: {
                    Image(systemName: "keyboard")
                        .frame(width: 44, height: 34)
                        .background(Color(.systemBackground), in: Capsule())
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to keys")
            }
        }
        .padding(.horizontal, 2)
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
            Hint(systemImage: "doc.on.doc",
                 text: "Copy their message, or a screenshot of the chat, then tap the button above.")
        case .reading:
            Working(text: "Reading what you copied…")
        case .generating:
            Working(text: "Writing replies…")
        case .failed(let reason):
            Hint(systemImage: "exclamationmark.triangle", text: reason)
        case .done:
            VStack(spacing: 6) {
                ScrollView {
                    VStack(spacing: 6) {
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
                Text(reply.text)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: inserted ? "checkmark.circle.fill" : "arrow.up.circle")
                    .foregroundStyle(inserted ? Color.green : Color.accentColor)
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
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

private struct Working: View {
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
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
                SystemKey(systemImage: "delete.left", action: actions.deleteBackward)
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

private struct CharacterKey: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(label.count == 1 ? .title3 : .callout)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.primary)
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct SystemKey: View {
    var systemImage: String? = nil
    var text: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let text {
                    Text(text).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color(.systemGray3), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Color.primary)
            .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
