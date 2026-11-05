import SwiftUI

@MainActor
final class MessagesScreenState: ObservableObject {
    @Published var insertedID: UUID?
    @Published var autoRead = false
    @Published var hasPhotos = true
    /// Showing who said what instead of the replies.
    @Published var reviewing = false
    /// Shares the keyboard's choice name, but each extension remembers its own.
    @Published var screenshotCount: Int = {
        let saved = UserDefaults.standard.integer(forKey: "screenshotCount")
        return (1...3).contains(saved) ? saved : 2
    }() {
        didSet { UserDefaults.standard.set(screenshotCount, forKey: "screenshotCount") }
    }
}

struct MessagesActions {
    var readLatest: () -> Void
    var insert: (ReplySuggestion) -> Void
    var expand: () -> Void
}

/// Same look as the Coax keyboard: one bar on top, then waiting, reading, or replies.
struct MessagesView: View {
    @ObservedObject var model: ReplyFlowModel
    @ObservedObject var screen: MessagesScreenState
    var actions: MessagesActions

    var body: some View {
        VStack(spacing: 8) {
            bar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            Button(action: actions.readLatest) {
                Label(screen.screenshotCount == 1 ? "Last screenshot" : "Last \(screen.screenshotCount)",
                      systemImage: "camera.viewfinder")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.coax, in: Capsule())
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { n in
                    Button {
                        screen.screenshotCount = n
                    } label: {
                        Text("\(n)")
                            .font(.footnote.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(n == screen.screenshotCount ? Color.coax : Color.clear, in: Circle())
                            .foregroundStyle(n == screen.screenshotCount ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Read \(n) screenshot\(n == 1 ? "" : "s")")
                }
            }
            .padding(4)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .waiting:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Color.coax).frame(width: 8, height: 8)
                    Text("Waiting for a screenshot…").font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.coaxSoft, in: Capsule())
                Text(screen.hasPhotos
                     ? "Take a screenshot of this chat and I'll read it right away."
                     : "Open the Coax app once and allow Photos, so I can see your screenshots.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .reading, .generating:
            VStack(spacing: 10) {
                if !model.previews.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(model.previews.indices, id: \.self) { i in
                            Image(uiImage: model.previews[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.coax, lineWidth: 2))
                        }
                    }
                    .accessibilityHidden(true)
                }
                HStack(spacing: 8) {
                    ProgressView()
                    Text(model.phase == .generating ? "Writing replies…"
                         : screen.autoRead ? "Reading your new screenshot…" : "Reading the chat…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .done where screen.reviewing:
            ChatReview(model: model) {
                screen.insertedID = nil
                screen.reviewing = false
            }
        case .done:
            ScrollView {
                VStack(spacing: 6) {
                    ReadSummaryButton(model: model) {
                        screen.reviewing = true
                        actions.expand()
                    }
                    ForEach(model.replies) { reply in
                        replyCard(reply)
                    }
                    MoodTagRow(model: model) { screen.insertedID = nil }
                    if model.replies.count > 1 {
                        Button("See all replies", action: actions.expand)
                            .font(.footnote)
                            .foregroundStyle(Color.coax)
                    }
                }
            }
        }
    }

    private func replyCard(_ reply: ReplySuggestion) -> some View {
        let inserted = screen.insertedID == reply.id
        return Button {
            actions.insert(reply)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = reply.label, !label.isEmpty {
                        Text(label.uppercased())
                            .font(.caption2.weight(.bold))
                            .kerning(0.4)
                            .foregroundStyle(inserted ? Color.coaxDone : Color.coax)
                    }
                    Text(reply.text)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: inserted ? "checkmark.circle.fill" : "arrow.up.circle")
                    .foregroundStyle(inserted ? Color.coaxDone : Color.coax)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inserted ? Color.coaxDone : Color.clear, lineWidth: 1.5))
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reply.label.map { "\($0): \(reply.text)" } ?? reply.text)
        .accessibilityHint("Puts this reply in the message box")
    }
}
