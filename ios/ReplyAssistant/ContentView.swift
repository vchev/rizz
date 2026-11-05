import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Home: one way to get replies, your recent chats, and setup only when
/// something is off (design review, Nov 5).
struct ContentView: View {
    @StateObject private var model = ReplyFlowModel(store: ChatStore.forUse)
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pasteFailed = false
    @State private var showSettings = false
    @State private var showReplies = false
    @State private var recent: [SavedChat] = []
    @State private var keyboardOn = KeyboardCheck.isAdded
    @State private var photosOn = RecentScreenshots.hasAccess
    @AppStorage("coax.howToDismissed") private var howToDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    /// Test builds only: runs first-time setup again (see ReplyAssistantApp).
    var onReplaySetup: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let banner { banner }
                    if !howToDismissed { howTo }
                    actions
                    recentChats
                    Button("Try it with an example chat") { open { await model.tryExample() } }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showReplies) {
                RepliesView(model: model)
            }
        }
        .accessibilityIdentifier("home")
        .tint(Color.coax)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            pickedItems = []
            open { await model.read(await loadImages(items)) }
        }
        .onChange(of: showReplies) { _, showing in
            if !showing { refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onAppear { refresh() }
        .sheet(isPresented: $showSettings) {
            SettingsView(onReplaySetup: onReplaySetup.map { replay in
                { showSettings = false; replay() }
            })
        }
        .alert("No screenshot on the clipboard", isPresented: $pasteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take a screenshot, tap the preview, tap Copy, then try Paste again.")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Wordmark(size: 30)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    /// One line, only when the keyboard or Photos is off.
    private var banner: AnyView? {
        let (title, fix): (String, () -> Void)
        if !keyboardOn {
            title = "Coax keyboard is off"
            fix = { openSettings() }
        } else if !photosOn {
            title = "Coax can't see your screenshots"
            fix = { Task { photosOn = await RecentScreenshots.requestAccess(); if !photosOn { openSettings() } } }
        } else {
            return nil
        }
        return AnyView(
            Button(action: fix) {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(title).fontWeight(.semibold)
                    Spacer()
                    Text("Turn on").fontWeight(.semibold).foregroundStyle(Color.coax)
                }
                .font(.subheadline)
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        )
    }

    /// Shown until closed: the three taps that matter.
    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Here's the move").font(.headline)
                Spacer()
                Button { withAnimation { howToDismissed = true } } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            Move(number: 1, text: "Screenshot the chat")
            Move(number: 2, text: "Tap the message box, then switch to Coax with 🌐")
            Move(number: 3, text: "Tap 1, 2 or 3")
        }
        .padding(14)
        .background(Color.coaxSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 3,
                         selectionBehavior: .ordered, matching: .screenshots) {
                Label("Get replies from a screenshot", systemImage: "camera.viewfinder")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryButton())
            Button("Paste") {
                if let image = UIPasteboard.general.image {
                    open { await model.read([image]) }
                } else {
                    pasteFailed = true
                }
            }
            .buttonStyle(OutlineButton())
        }
    }

    @ViewBuilder private var recentChats: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent chats").font(.headline).padding(.bottom, 6)
                ForEach(recent) { chat in
                    Button { open { await model.open(chat) } } label: {
                        RecentRow(chat: chat)
                    }
                    .buttonStyle(.plain)
                    if chat.id != recent.last?.id { Divider().padding(.leading, 48) }
                }
            }
        }
    }

    // MARK: Actions

    private func open(_ work: @escaping () async -> Void) {
        showReplies = true
        Task { await work() }
    }

    private func refresh() {
        keyboardOn = KeyboardCheck.isAdded
        photosOn = RecentScreenshots.hasAccess
        recent = Array((ChatStore.forUse?.chats ?? [])
            .sorted { $0.updated > $1.updated }
            .prefix(6))
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return images
    }
}

private struct Move: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.coax, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

/// A saved chat: their last message and when.
private struct RecentRow: View {
    var chat: SavedChat

    private static let colors: [Color] = [.coax, .teal, .purple, .orange, .pink, .indigo]

    var body: some View {
        let last = chat.messages.last(where: { $0.speaker == .them }) ?? chat.messages.last
        let initial = last.map { String($0.text.prefix(1)).uppercased() } ?? "?"
        let color = Self.colors[chat.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 97 } % Self.colors.count]
        HStack(spacing: 12) {
            Text(initial)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(last?.text ?? "Chat")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(chat.updated, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
}
