import SwiftUI

/// "Read N messages" — tap it to see who said what.
/// Used by the keyboard and the Messages app; checking is optional, replies
/// come first.
struct ReadSummaryButton: View {
    @ObservedObject var model: ReplyFlowModel
    var action: () -> Void

    var body: some View {
        if let text = Self.summary(model) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("Check")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.coax)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Color.coax)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows who said what, so you can fix it")
        }
    }

    static func summary(_ model: ReplyFlowModel) -> String? {
        guard let last = model.messages.last(where: { $0.speaker == .them }) else { return nil }
        let count = model.readCount
        var text = "Read \(count) message\(count == 1 ? "" : "s")"
        if model.earlierCount > 0 { text += " (+\(model.earlierCount) from before)" }
        return text + ". Their last: \u{201C}\(last.text)\u{201D}"
    }
}

/// The chat as Coax read it. Tap a message to switch who sent it, then get
/// new replies for the fixed chat.
struct ChatReview: View {
    @ObservedObject var model: ReplyFlowModel
    /// Called after new replies are asked for, so the caller can go back to them.
    var onRegenerate: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            Text("Tap a message to switch who sent it")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if index == model.latestIndex && index > 0 {
                                Divider().overlay(Text("Your latest screenshot")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .background(Color(.systemBackground)))
                                    .padding(.vertical, 6)
                            }
                            ReviewBubble(message: message)
                                .id(message.id)
                                .onTapGesture { model.flipSpeaker(of: message) }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Button {
                onRegenerate()
                Task { await model.generate() }
            } label: {
                Label(model.editedSinceReplies ? "Get replies for the fixed chat" : "Get new replies",
                      systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(model.editedSinceReplies ? Color.coax : Color(.secondarySystemBackground),
                                in: Capsule())
                    .foregroundStyle(model.editedSinceReplies ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
    }
}

private struct ReviewBubble: View {
    var message: ChatMessage

    var body: some View {
        let mine = message.speaker == .you
        HStack {
            if mine { Spacer(minLength: 36) }
            Text(message.text)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(mine ? Color.coax : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(mine ? Color.white : Color.primary)
                .contentShape(Rectangle())
            if !mine { Spacer(minLength: 36) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : "Them"): \(message.text)")
        .accessibilityHint("Double-tap to switch who sent it")
    }
}
