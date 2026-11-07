import SwiftUI
import UIKit

/// Shows the suggested replies and the conversation they came from.
struct ReplyFlowView: View {
    @ObservedObject var model: ReplyFlowModel
    @State private var copiedID: UUID?

    var body: some View {
        List {
            if model.service.isSample {
                Section {
                    Label("These are sample replies. Real ones arrive once the reply engine is connected.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            repliesSection

            if !model.messages.isEmpty {
                Section {
                    ForEach(model.messages) { message in
                        MessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture { model.flipSpeaker(of: message) }
                    }
                    .onDelete { model.delete(at: $0) }
                } header: {
                    Text("What I read")
                } footer: {
                    Text("Tap a message to switch who sent it. Swipe left to remove one.")
                }
            }
        }
        .animation(.default, value: model.replies)
        .animation(.default, value: model.messages)
    }

    @ViewBuilder
    private var repliesSection: some View {
        Section {
            switch model.phase {
            case .waiting:
                EmptyView()
            case .reading:
                ProgressRow(text: "Reading your screenshot…")
            case .generating:
                ProgressRow(text: "Writing replies…")
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .done:
                ForEach(model.replies) { reply in
                    Button {
                        UIPasteboard.general.string = reply.text
                        if copiedID != reply.id { model.recordPick(reply) }
                        copiedID = reply.id
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let label = reply.label, !label.isEmpty {
                                    Text(label.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .kerning(0.4)
                                        .foregroundStyle(Color.coax)
                                }
                                Text(reply.text)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: copiedID == reply.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedID == reply.id ? Color.coaxDone : Color.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if model.phase == .done {
                SayPickRow(model: model) { copiedID = nil }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                MoodTagRow(model: model) { copiedID = nil }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            if !model.messages.isEmpty && !model.isBusy {
                Button {
                    Task { await model.generate() }
                } label: {
                    Label(model.editedSinceReplies ? "Get replies for the edited chat" : "Get new replies",
                          systemImage: "arrow.clockwise")
                }
            }
        } header: {
            if model.phase == .done { Text("Tap a reply to copy it") }
        }
    }
}

private struct ProgressRow: View {
    var text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct MessageRow: View {
    var message: ChatMessage

    var body: some View {
        let mine = message.speaker == .you
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(mine ? "You" : "Them")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mine ? Color.accentColor : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(mine ? Color.white : Color.primary)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Brand colors

/// Coax's colors (decided Nov 4: a blue close to the iMessage keyboard).
/// Defined in code so the keyboard, which has no asset catalog, matches the app.
extension Color {
    /// Main color: buttons, links, the reply arrow.
    static let coax = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3D / 255, green: 0x9B / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0x0A / 255, green: 0x7C / 255, blue: 0xFF / 255, alpha: 1) })
    /// Soft tint behind small numbers and tags.
    static let coaxSoft = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.12)
        : UIColor(red: 0xE3 / 255, green: 0xF0 / 255, blue: 0xFF / 255, alpha: 1) })
    /// "Done" moments, like a reply that was typed in.
    static let coaxDone = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        : UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1) })
}

/// Funny · Flirty · Sweet · Chill · Bold · Shorter. Tapping one gets 3 new replies in that
/// mood; tapping the lit one again goes back to mixed moods.
/// With `sayPicks` (the keyboard, which has no room for a second row) the "What should it
/// say?" picks follow the moods in the same row, after a divider.
struct MoodTagRow: View {
    @ObservedObject var model: ReplyFlowModel
    var background: Color = Color(.secondarySystemBackground)
    var sayPicks = false
    var onYourOwn: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ReplyTone.allCases) { tone in
                    let on = model.tone == tone
                    CoaxChip(title: tone.label, on: on, background: background) {
                        onTap()
                        Task { await model.generate(tone: on ? nil : tone) }
                    }
                    .disabled(model.isBusy)
                }
                if sayPicks {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 2)
                        .accessibilityHidden(true)
                    SayPickChips(model: model, background: background, onYourOwn: onYourOwn, onTap: onTap)
                }
            }
        }
        // A fade at the right edge shows there's more to swipe to.
        .mask(HStack(spacing: 0) {
            Color.black
            if sayPicks {
                LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
            }
        })
    }
}

// MARK: - Tell Coax what to say

extension ReplyFlowModel {
    /// The quick pick that's on, if the current line is one of them.
    var sayPick: SayPick? { SayPick.allCases.first { $0.intent == intent } }

    /// True when the person typed their own line.
    var hasOwnIntent: Bool {
        sayPick == nil && !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Turns a quick pick on (or off, if it's already on) and gets fresh replies in the same mood.
    func toggle(_ pick: SayPick) async {
        intent = sayPick == pick ? "" : pick.intent
        await generate(tone: tone)
    }

    /// Drops the line and gets fresh replies in the same mood.
    func clearIntent() async {
        intent = ""
        await generate(tone: tone)
    }
}

/// Yes · No · Ask them out · Change topic · Your own.
struct SayPickChips: View {
    @ObservedObject var model: ReplyFlowModel
    var background: Color
    var onYourOwn: () -> Void
    var onTap: () -> Void

    var body: some View {
        ForEach(SayPick.allCases) { pick in
            CoaxChip(title: pick.label, on: model.sayPick == pick, background: background) {
                onTap()
                Task { await model.toggle(pick) }
            }
            .accessibilityHint(Text(model.sayPick == pick ? "Turns this off" : "Gets replies that \(pick.intent.lowercased())"))
            .disabled(model.isBusy)
        }
        CoaxChip(title: "Type what to say", systemImage: "pencil", on: model.hasOwnIntent, background: background,
                 action: onYourOwn)
            .accessibilityHint("Type what you want the reply to say")
            .disabled(model.isBusy)
    }
}

/// A pill-shaped tag. Lit (blue) when on.
struct CoaxChip: View {
    var title: String
    var systemImage: String? = nil
    var on: Bool
    var background: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(on ? Color.coax : background, in: Capsule())
            .foregroundStyle(on ? Color.white : Color.primary)
            // Looks 32 points tall, taps like 44 (Apple's minimum).
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The app and the Messages app have room for their own row: "What should it say?", the
/// quick picks, and a line to type your own (with Write, and Remove once one is in use).
struct SayPickRow: View {
    @ObservedObject var model: ReplyFlowModel
    var background: Color = Color(.secondarySystemBackground)
    /// Called when the typing line opens (the Messages app grows so the keyboard fits).
    var onStartTyping: () -> Void = {}
    var onTap: () -> Void = {}

    @State private var typing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What should it say?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    SayPickChips(model: model, background: background, onYourOwn: startTyping, onTap: {
                        typing = false
                        onTap()
                    })
                }
            }
            if typing {
                HStack(spacing: 8) {
                    TextField("e.g. say I'm busy, but free Sunday", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(write)
                        .onChange(of: draft) { _, new in
                            if new.count > ReplyFlowModel.maxIntent { draft = String(new.prefix(ReplyFlowModel.maxIntent)) }
                        }
                        .accessibilityLabel("What should the reply say?")
                    Button("Get replies", action: write)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.coax)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                }
                Button(model.hasOwnIntent ? "Remove your line" : "Cancel") {
                    typing = false
                    focused = false
                    if model.hasOwnIntent {
                        onTap()
                        Task { await model.clearIntent() }
                    }
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(Color.coax)
            } else if model.hasOwnIntent {
                Text("Saying: \u{201C}\(model.intent)\u{201D}")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func startTyping() {
        draft = model.hasOwnIntent ? model.intent : ""
        typing = true
        onStartTyping()
        focused = true
    }

    private func write() {
        let line = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !model.isBusy else { return }
        typing = false
        focused = false
        onTap()
        Task { await model.say(String(line.prefix(ReplyFlowModel.maxIntent))) }
    }
}
