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
            Text(["Tap a message to switch who sent it", model.timing].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Stays up (dimmed) while new replies load after a move.
            if model.canReorderScreenshots || (model.isBusy && model.previews.count > 1) {
                ScreenshotOrderStrip(model: model)
            }
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
            if model.canStartFresh {
                Button("Wrong chat? Start fresh with just this screenshot") {
                    model.startFresh()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.coax)
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

/// The screenshots Coax read, oldest first (Vanessa, Nov 6: "they can just
/// move it on the screen"). Drag one sideways to change the order; Coax
/// rejoins the chat in that order and writes new replies. Auto-sort by the
/// chat's dates is right most of the time, so this stays on the Check screen,
/// off the main path.
struct ScreenshotOrderStrip: View {
    @ObservedObject var model: ReplyFlowModel
    @State private var dragging: Int?
    @State private var offset: CGFloat = 0

    private let width: CGFloat = 36
    private let gap: CGFloat = 12

    var body: some View {
        VStack(spacing: 4) {
            Text("Screenshots, oldest first. Drag one to fix the order.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: gap) {
                ForEach(Array(model.previews.enumerated()), id: \.offset) { index, image in
                    thumbnail(index, image)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(model.isBusy ? 0.5 : 1)
        .allowsHitTesting(!model.isBusy)
        .accessibilityIdentifier("screenshotOrder")
    }

    private func thumbnail(_ index: Int, _ image: UIImage) -> some View {
        let count = model.previews.count
        let lifted = dragging == index
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 1.8)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.coax, lineWidth: lifted ? 3 : 1.5))
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .frame(width: 18, height: 18)
                    .background(Color.coax, in: Circle())
                    .foregroundStyle(.white)
                    .offset(x: -6, y: -6)
            }
            .scaleEffect(lifted ? 1.12 : 1)
            .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 6, y: 3)
            .offset(x: lifted ? offset : 0)
            .zIndex(lifted ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragging = index
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        let slots = Int((value.translation.width / (width + gap)).rounded())
                        let target = min(max(index + slots, 0), count - 1)
                        withAnimation(.spring(duration: 0.25)) {
                            dragging = nil
                            offset = 0
                        }
                        move(index, to: target)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Screenshot \(index + 1) of \(count)")
            .accessibilityHint("Swipe up or down to move it earlier or later")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(index, to: min(index + 1, count - 1))
                case .decrement: move(index, to: max(index - 1, 0))
                @unknown default: break
                }
            }
    }

    private func move(_ from: Int, to: Int) {
        guard from != to else { return }
        Task { await model.moveScreenshot(from: from, to: to) }
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
