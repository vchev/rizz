import Photos
import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = ReplyFlowModel(store: ChatStore.forUse)
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pasteFailed = false
    /// Test builds only: runs first-time setup again (see ReplyAssistantApp).
    var onReplaySetup: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .waiting {
                    startScreen
                } else {
                    ReplyFlowView(model: model)
                }
            }
            .navigationTitle("Coax")
            .toolbar {
                #if DEBUG
                if model.phase == .waiting, let onReplaySetup {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Show setup again") { onReplaySetup() }
                    }
                }
                #endif
                if model.phase != .waiting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New") {
                            pickedItems = []
                            model.reset()
                        }
                        .disabled(model.isBusy)
                    }
                }
            }
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await model.read(await loadImages(items)) }
        }
        .task {
            // Ask for Photos up front: the keyboard can't ask, and it needs
            // this to read your latest screenshots.
            // Skipped in UI tests, where the system prompt would block the run.
            let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            if !uiTesting, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                _ = await RecentScreenshots.requestAccess()
            }
        }
        .alert("No screenshot on the clipboard", isPresented: $pasteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take a screenshot, tap the preview, tap Copy, then try Paste again.")
        }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)
                Text("Get replies right in your chats")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                KeyboardSetupCard()

                BackTapCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("How to use it").font(.headline)
                    Step(number: 1, text: "In Hinge, Messages or any chat, scroll up one screen and take a screenshot, then scroll back down and take another.")
                    Step(number: 2, text: "Tap the message box, then hold the 🌐 key and pick Coax.")
                    Step(number: 3, text: "Tap the screenshots button (tap the number to pick 1, 2 or 3), then tap a reply to type it in.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Button {
                    Task { await model.tryExample() }
                } label: {
                    Label("Try it with an example chat", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Or try it here with a screenshot")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: 5,
                                 selectionBehavior: .ordered, matching: .images) {
                        Label("Choose", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let image = UIPasteboard.general.image {
                            Task { await model.read([image]) }
                        } else {
                            pasteFailed = true
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(24)
        }
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

private struct KeyboardSetupCard: View {
    @Environment(\.openURL) private var openURL
    @State private var photosAllowed = RecentScreenshots.hasAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Turn on the keyboard (once)").font(.headline)
            Step(number: 1, text: "Tap Open Settings below, then Keyboards.")
            Step(number: 2, text: "Turn on Coax.")
            Step(number: 3, text: "Turn on Allow Full Access. iPhone shows a warning for every keyboard that goes online. We need it to read what you copy and fetch replies. Nothing you type is recorded or sent; only the chat text goes out, and only when you tap a Coax button.")
            Step(number: 4, text: "Allow Photos access, so the keyboard can read your latest screenshots. They're read on your phone and never uploaded.")
            Button {
                Task { photosAllowed = await RecentScreenshots.requestAccess() }
            } label: {
                Label(photosAllowed ? "Photos access allowed" : "Allow Photos access",
                      systemImage: photosAllowed ? "checkmark.circle" : "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(photosAllowed)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Optional and even faster: double-tap the back of the phone to read the
/// chat; the replies then wait in the Coax keyboard.
private struct BackTapCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Even faster: double-tap the back of your phone").font(.headline)
            Text("Optional. Coax reads the chat on screen, and the replies wait in the Coax keyboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let link = AppConfig.backTapShortcutLink {
                Step(number: 1, text: "Tap Add Shortcut below, then Add Shortcut again.")
                Button {
                    openURL(link)
                } label: {
                    Label("Add Shortcut", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Step(number: 1, text: "In the Shortcuts app, tap +, add Take Screenshot, then add Get Coax Replies. Name it Coax.")
            }
            Step(number: 2, text: "Open the Settings app › Accessibility › Touch › Back Tap › Double Tap, and pick Coax. (iPhone 15 Pro or newer: you can use the Action button instead.)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct Step: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.footnote.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

#Preview {
    ContentView()
}
