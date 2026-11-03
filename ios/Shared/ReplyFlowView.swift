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
                        copiedID = reply.id
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(reply.text)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: copiedID == reply.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedID == reply.id ? Color.green : Color.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                }
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
