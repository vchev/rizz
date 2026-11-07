import SwiftUI
import UIKit

/// Replies for one chat: the chat as real bubbles, then the same 1·2·3 cards
/// and tags as the keyboard. Fixing who said what lives in a sheet. After a
/// reply is copied, a bar stays at the bottom with the next step (paste it in
/// your chat) and a way out ("Try another chat"), so the screen has an ending.
struct RepliesView: View {
    @ObservedObject var model: ReplyFlowModel
    @State private var copiedID: UUID?
    @State private var showFix = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.service.isSample {
                    Label("These are sample replies. Real ones arrive once the reply engine is connected.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                chat
                Text("Pick a reply").font(.title2.bold())
                replies
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if let number = copiedNumber {
                NextStepBar(number: number,
                            pickAnother: { copiedID = nil },
                            anotherChat: { dismiss() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Wordmark(size: 18) }
        }
        .sheet(isPresented: $showFix) {
            NavigationStack {
                ChatReview(model: model) { showFix = false }
                    .padding(.horizontal, 16)
                    .navigationTitle("Fix the chat")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showFix = false } }
                    }
            }
            .presentationDetents([.large])
        }
        .animation(.default, value: model.replies)
        .animation(.default, value: copiedID)
    }

    /// The last few messages, with a way to fix who said what.
    @ViewBuilder private var chat: some View {
        if !model.messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(model.messages.suffix(3)) { ChatBubble(message: $0) }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                HStack {
                    Text("Read \(model.readCount) message\(model.readCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Fix the chat") { showFix = true }
                        .fontWeight(.semibold)
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder private var replies: some View {
        switch model.phase {
        case .waiting, .reading:
            Working(text: "Reading your screenshot…")
        case .generating:
            Working(text: "Writing replies…")
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            if !model.messages.isEmpty {
                Button("Try again") { Task { await model.generate() } }
                    .buttonStyle(SecondaryButton())
            }
        case .done:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.replies.enumerated()), id: \.element.id) { index, reply in
                    CoaxReplyCard(number: index + 1, reply: reply, copied: copiedID == reply.id) {
                        UIPasteboard.general.string = reply.text
                        if copiedID != reply.id { model.recordPick(reply) }
                        copiedID = reply.id
                    }
                }
                TellCoaxRow(model: model) { copiedID = nil }
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    MoodTagRow(model: model) { copiedID = nil }
                    TagChip(title: "New ones", systemImage: "arrow.clockwise") { regenerate(model.tone) }
                }
                .padding(.top, 4)
            }
        }
    }

    private func regenerate(_ tone: ReplyTone?) {
        copiedID = nil
        Task { await model.generate(tone: tone) }
    }

    private var copiedNumber: Int? {
        guard let copiedID, let index = model.replies.firstIndex(where: { $0.id == copiedID }) else { return nil }
        return index + 1
    }
}

/// Stays up after a copy until you act: what to do next, and a way out.
private struct NextStepBar: View {
    var number: Int   // the copied reply, for VoiceOver
    var pickAnother: () -> Void
    var anotherChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Copied! Paste it in your chat", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .accessibilityLabel("Reply \(number) copied. Paste it in your chat")
                .foregroundStyle(Color.coaxDone)
            Text("Go back to your chat, tap the message box, then tap Paste.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Pick another reply", action: pickAnother)
                    .buttonStyle(SecondaryButton())
                Button("Try another chat", action: anotherChat)
                    .buttonStyle(PrimaryButton())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

private struct Working: View {
    var text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
