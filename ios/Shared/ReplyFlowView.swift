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
                TellCoaxRow(model: model) { copiedID = nil }
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
/// With `tellCoax` (the keyboard, which has no room for a second row) the row starts with
/// "Tell Coax what to say".
struct MoodTagRow: View {
    @ObservedObject var model: ReplyFlowModel
    var background: Color = Color(.secondarySystemBackground)
    var tellCoax = false
    var onTellCoax: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if tellCoax {
                    CoaxChip(title: "Tell Coax what to say", systemImage: "pencil", on: model.hasIntent,
                             background: Color.coaxSoft, tint: Color.coax, action: onTellCoax)
                        .accessibilityHint("Type what the reply should say, and Coax writes 3")
                        .disabled(model.isBusy)
                }
                ForEach(ReplyTone.allCases) { tone in
                    let on = model.tone == tone
                    CoaxChip(title: tone.label, on: on, background: background) {
                        onTap()
                        Task { await model.generate(tone: on ? nil : tone) }
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        // A fade at the right edge shows there's more to swipe to.
        .mask(HStack(spacing: 0) {
            Color.black
            if tellCoax {
                LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
            }
        })
    }
}

// MARK: - Tell Coax what to say

/// "Tell Coax what to say" (Vanessa, Nov 7): type what you want to say, like "say I'm busy
/// but free Sunday", and Coax brainstorms 3 replies that say it. The mood still sets the sound.
extension ReplyFlowModel {
    /// True while a line is in use.
    var hasIntent: Bool { !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Drops the line and gets fresh replies in the same mood.
    func clearIntent() async {
        intent = ""
        await generate(tone: tone)
    }
}

/// A pill-shaped tag. Lit (blue) when on.
struct CoaxChip: View {
    var title: String
    var systemImage: String? = nil
    var on: Bool
    var background: Color
    var tint: Color = .primary
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
            .foregroundStyle(on ? Color.white : tint)
            // Looks 32 points tall, taps like 44 (Apple's minimum).
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The app and the Messages app have room for the line itself: type what to say, tap
/// Get replies, and Coax writes 3. Once a line is in use it shows, with Remove.
struct TellCoaxRow: View {
    @ObservedObject var model: ReplyFlowModel
    /// Called when typing starts (the Messages app grows so the keyboard fits).
    var onStartTyping: () -> Void = {}
    var onTap: () -> Void = {}

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell Coax what to say")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("e.g. say I'm busy, but free Sunday", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(write)
                    .onChange(of: draft) { _, new in
                        if new.count > ReplyFlowModel.maxIntent { draft = String(new.prefix(ReplyFlowModel.maxIntent)) }
                    }
                    .onChange(of: focused) { _, now in if now { onStartTyping() } }
                    .accessibilityLabel("Tell Coax what the reply should say")
                Button("Get replies", action: write)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.coax)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
            if model.hasIntent {
                HStack(spacing: 6) {
                    Text("Saying: \u{201C}\(model.intent)\u{201D}")
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Remove") {
                        draft = ""
                        onTap()
                        Task { await model.clearIntent() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.coax)
                    .disabled(model.isBusy)
                }
                .font(.footnote)
            }
        }
    }

    private func write() {
        let line = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !model.isBusy else { return }
        focused = false
        draft = ""
        onTap()
        Task { await model.say(String(line.prefix(ReplyFlowModel.maxIntent))) }
    }
}
