import SwiftUI
import UIKit

/// What the keyboard needs to know about its surroundings. Refreshed each time it appears.
@MainActor
final class KeyboardState: ObservableObject {
    @Published var hasFullAccess = false
    @Published var showsGlobe = true
    @Published var insertedID: UUID?
    @Published var panel: Panel = .keys
    @Published var shifted = true
    @Published var showingSymbols = false
    /// True while the keyboard is watching for a new screenshot to read by itself.
    @Published var watching = false
    /// True when the current read was started by a new screenshot, not a tap.
    @Published var autoRead = false
    /// How many recent screenshots to read (1 to 3). Remembered between uses;
    /// this number is the only thing the keyboard saves.
    @Published var screenshotCount: Int = {
        let saved = UserDefaults.standard.integer(forKey: "screenshotCount")
        return (1...3).contains(saved) ? saved : 2
    }() {
        didSet { UserDefaults.standard.set(screenshotCount, forKey: "screenshotCount") }
    }

    enum Panel { case keys, replies, fullAccessHelp }
}

/// The Coax keyboard: a plain typing keyboard plus a reply bar. Copy their
/// message (or a screenshot), tap the reply bar, and tap a reply to type it
/// into the chat. Nothing goes over the network unless that bar is tapped,
/// and keystrokes are never stored or sent.
final class KeyboardViewController: UIInputViewController {
    static let height: CGFloat = 290

    private let model = ReplyFlowModel()
    private let state = KeyboardState()
    private let watcher = ScreenshotWatcher()

    override func viewDidLoad() {
        super.viewDidLoad()
        watcher.onNewScreenshot = { [weak self] in self?.newScreenshotTaken() }

        let root = KeyboardView(
            model: model,
            state: state,
            actions: KeyboardActions(
                getRepliesFromScreenshots: { [weak self] in self?.readScreenshots(auto: false) },
                getReplies: { [weak self] in self?.readClipboard() },
                insert: { [weak self] reply in self?.insert(reply) },
                type: { [weak self] text in self?.textDocumentProxy.insertText(text) },
                deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
                nextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
            )
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)

        let height = view.heightAnchor.constraint(equalToConstant: Self.height)
        height.priority = .defaultHigh + 1
        NSLayoutConstraint.activate([
            height,
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshState()
        showShortcutReplies()
        startWatching()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        watcher.stop()
        state.watching = false
    }

    /// While the keyboard is open, a new screenshot is read without a tap.
    /// Needs Full Access (for the internet) and the app's Photos access. The
    /// keyboard may misreport Photos access, so seeing a screenshot is the test.
    private func startWatching() {
        guard hasFullAccess else {
            state.watching = false
            return
        }
        watcher.start()
        state.watching = RecentScreenshots.newest() != nil
    }

    private func newScreenshotTaken() {
        refreshState()
        guard hasFullAccess, !model.isBusy else { return }
        state.panel = .replies
        readScreenshots(auto: true)
    }

    /// Replies the Back Tap shortcut left for us: show them straight away.
    private func showShortcutReplies() {
        guard hasFullAccess, !model.isBusy, let pending = PendingReplies.take() else { return }
        state.insertedID = nil
        model.show(pending)
        state.panel = .replies
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        refreshState()
    }

    private func refreshState() {
        if state.hasFullAccess != hasFullAccess { state.hasFullAccess = hasFullAccess }
        if state.showsGlobe != needsInputModeSwitchKey { state.showsGlobe = needsInputModeSwitchKey }
    }

    private func insert(_ reply: ReplySuggestion) {
        textDocumentProxy.insertText(reply.text)
        state.insertedID = reply.id
        state.shifted = false
    }

    private func readScreenshots(auto: Bool) {
        refreshState()
        guard hasFullAccess else { return }
        state.insertedID = nil
        state.autoRead = auto
        let count = state.screenshotCount
        Task { @MainActor in await model.readLatestScreenshots(count: count) }
    }

    /// Without Full Access, iOS gives the keyboard neither the clipboard nor the internet.
    private func readClipboard() {
        refreshState()
        guard hasFullAccess else { return }
        state.insertedID = nil
        state.autoRead = false
        let pasteboard = UIPasteboard.general
        Task { @MainActor in
            if pasteboard.hasImages, let image = pasteboard.image {
                await model.read([image])
            } else if pasteboard.hasStrings, let text = pasteboard.string {
                await model.readText(text)
            } else {
                model.phase = .failed("Nothing copied yet. Long-press their message and tap Copy, or take a screenshot, tap it, and tap Copy.")
            }
        }
    }
}
