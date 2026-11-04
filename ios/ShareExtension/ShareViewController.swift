import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "Coax" item in the share sheet. Reads the shared
/// screenshot(s) and shows reply suggestions right there, ready to copy.
final class ShareViewController: UIViewController {
    private let model = ReplyFlowModel(store: ChatStore.forUse)

    override func viewDidLoad() {
        super.viewDidLoad()

        let root = NavigationStack {
            ReplyFlowView(model: model)
                .navigationTitle("Coax")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { [weak self] in self?.finish() }
                    }
                }
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        model.phase = .reading
        Task { @MainActor in
            let images = await loadSharedImages()
            await model.read(images)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func loadSharedImages() async -> [UIImage] {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        var images: [UIImage] = []
        for provider in providers {
            if let image = await Self.loadImage(from: provider) {
                images.append(image)
            }
        }
        return images
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        // Most apps share image data; the screenshot editor may share a UIImage.
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        if let data, let image = UIImage(data: data) { return image }

        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}
