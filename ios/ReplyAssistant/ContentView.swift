import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = ReplyFlowModel()
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pasteFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .waiting {
                    startScreen
                } else {
                    ReplyFlowView(model: model)
                }
            }
            .navigationTitle("Reply Assistant")
            .toolbar {
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
        .alert("No screenshot on the clipboard", isPresented: $pasteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take a screenshot, tap the preview, tap Copy, then try Paste again.")
        }
    }

    private var startScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Get replies that sound like you")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Pick a screenshot of the chat. Or, from Photos or the screenshot preview, tap Share and choose Reply Assistant.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $pickedItems, maxSelectionCount: 5,
                         selectionBehavior: .ordered, matching: .images) {
                Label("Choose screenshots", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                if let image = UIPasteboard.general.image {
                    Task { await model.read([image]) }
                } else {
                    pasteFailed = true
                }
            } label: {
                Label("Paste screenshot", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Spacer()
        }
        .padding(24)
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

#Preview {
    ContentView()
}
