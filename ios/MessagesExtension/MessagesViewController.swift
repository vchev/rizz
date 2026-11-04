import Messages
import SwiftUI
import UIKit

/// The Coax iMessage app: tap + in Messages, pick Coax, and it waits for a
/// screenshot of the chat. Take one and it reads it, writes 3 replies, and
/// tapping a reply puts it in the Messages text box, ready to send.
/// iMessage apps can use the internet without Full Access, unlike keyboards.
final class MessagesViewController: MSMessagesAppViewController {
    private let model = ReplyFlowModel()
    private let screen = MessagesScreenState()
    private let watcher = ScreenshotWatcher()

    override func viewDidLoad() {
        super.viewDidLoad()
        watcher.onNewScreenshot = { [weak self] in self?.read(auto: true) }

        let root = MessagesView(
            model: model,
            screen: screen,
            actions: MessagesActions(
                readLatest: { [weak self] in self?.read(auto: false) },
                insert: { [weak self] reply in self?.insert(reply) },
                expand: { [weak self] in self?.requestPresentationStyle(.expanded) }
            )
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
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
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        if !model.isBusy && model.phase != .done { model.reset() }
        watcher.start()
        screen.hasPhotos = RecentScreenshots.newest() != nil || RecentScreenshots.hasAccess
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        watcher.stop()
    }

    private func read(auto: Bool) {
        guard !model.isBusy else { return }
        screen.insertedID = nil
        screen.autoRead = auto
        let count = screen.screenshotCount
        Task { @MainActor in await model.readLatestScreenshots(count: count) }
    }

    private func insert(_ reply: ReplySuggestion) {
        activeConversation?.insertText(reply.text) { _ in }
        screen.insertedID = reply.id
        // Back to the small panel so the text box with the reply is in view.
        if presentationStyle == .expanded { requestPresentationStyle(.compact) }
    }
}
