import SwiftUI
import UIKit

/// Replies for one chat: the chat as real bubbles, then the same 1·2·3 cards
/// and tags as the keyboard. Fixing who said what lives in a sheet.
struct RepliesView: View {
    @ObservedObject var model: ReplyFlowModel
    @State private var copiedID: UUID?
    @State private var showFix = false
    @State private var toast: String?

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
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 16)
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
        .animation(.default, value: toast)
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
                        copiedID = reply.id
                        show("Copied. Paste it in your chat.")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ReplyTone.allCases) { tone in
                            TagChip(title: tone.label) { regenerate(tone) }
                        }
                        TagChip(title: "New ones", systemImage: "arrow.clockwise") { regenerate(nil) }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func regenerate(_ tone: ReplyTone?) {
        copiedID = nil
        Task { await model.generate(tone: tone) }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
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
