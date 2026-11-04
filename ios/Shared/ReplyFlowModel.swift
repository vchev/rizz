import SwiftUI
import UIKit

/// Screenshot(s) in, reply suggestions out. Shared by the app and the share extension.
@MainActor
final class ReplyFlowModel: ObservableObject {
    enum Phase: Equatable {
        case waiting        // no screenshot yet
        case reading        // OCR running
        case generating     // asking for replies
        case done
        case failed(String)
    }

    @Published var phase: Phase = .waiting
    @Published var messages: [ChatMessage] = []
    @Published var replies: [ReplySuggestion] = []
    /// Set when the user edits the conversation after replies came back.
    @Published var editedSinceReplies = false
    /// The screenshots being read, shown small while Coax reads them.
    @Published var previews: [UIImage] = []
    /// How many messages the latest screenshots showed. `messages` can hold
    /// more: the earlier part of the same chat, saved on the phone.
    @Published var readCount = 0
    /// The message the user started a quoted reply to (Bumble's bar above the text box).
    var replyingTo: String?

    let service: ReplyService
    private let reader = ScreenshotReader()
    /// Where chats are kept between uses. nil = don't keep them (tests).
    let store: ChatStore?
    /// Ties reads to one chat when the caller knows which (the Messages conversation).
    var chatKey: String?
    private var chatID: String?

    /// The most recent messages sent for replies (the server reads up to 80).
    nonisolated static let maxMessagesSent = 60

    init(service: ReplyService = ReplyServices.makeDefault(), store: ChatStore? = nil) {
        self.service = service
        self.store = store
    }

    /// Where the latest screenshots' messages start in `messages` (the rest
    /// were saved earlier). nil = all of `messages` came from them.
    private var latestStart: Int?

    /// Saved messages from before the latest screenshots.
    var earlierCount: Int { max(messages.count - readCount, 0) }

    /// Where to draw the "Your latest screenshot" line in the chat review.
    var latestIndex: Int { min(latestStart ?? earlierCount, messages.count) }

    /// Keeps what was just read and joins it to the saved chat it belongs to.
    private func use(_ read: [ChatMessage]) {
        readCount = read.count
        guard let store, !read.isEmpty else {
            messages = read
            chatID = nil
            latestStart = nil
            return
        }
        let chat = store.remember(read, key: chatKey)
        chatID = chat.id
        messages = chat.messages
        latestStart = chat.latest?.lowerBound
    }

    /// Whether "Wrong chat? Start fresh" can split off the latest screenshot.
    var canStartFresh: Bool { earlierCount > 0 && chatID != nil }

    /// The latest screenshot was joined to the wrong saved chat: keep it on its own.
    func startFresh() {
        guard let store, let chatID, let fresh = store.startFresh(chatID) else { return }
        self.chatID = fresh.id
        messages = fresh.messages
        readCount = fresh.messages.count
        latestStart = nil
        editedSinceReplies = true
    }

    private func saveEdits() {
        guard let store, let chatID else { return }
        store.update(chatID, messages: messages)
    }

    var isBusy: Bool { phase == .reading || phase == .generating }

    func read(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            phase = .failed("No screenshot came through. Try sharing it again.")
            return
        }
        phase = .reading
        replies = []
        messages = []
        do {
            var all: [ChatMessage] = []
            replyingTo = nil
            for image in images {
                let chat = try await reader.readChat(image)
                all = Transcript.append(chat.messages, to: all)
                replyingTo = chat.replyingTo ?? replyingTo
            }
            use(all)
            guard !all.isEmpty else {
                phase = .failed("Couldn't find any messages in that screenshot. Try one that shows the chat bubbles.")
                return
            }
            await generate()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The keyboard's "last N screenshots" button (1 to 3).
    func readLatestScreenshots(count: Int = 2) async {
        phase = .reading
        replies = []
        messages = []
        previews = []
        do {
            let shots = try await RecentScreenshots.latestWithDates(min(max(count, 1), 3))
            var parts: [[ChatMessage]] = []
            var dates: [Date] = []
            replyingTo = nil
            for shot in shots {   // oldest first, so the newest bar wins
                let chat = try await reader.readChat(shot.image)
                parts.append(chat.messages)
                dates.append(shot.taken)
                replyingTo = chat.replyingTo ?? replyingTo
            }
            let kept = Transcript.sameChat(parts, taken: dates)
            previews = kept.map { shots[$0].image }
            let all = Transcript.joinBestOrder(kept.map { parts[$0] })
            use(all)
            guard !all.isEmpty else {
                phase = .failed("Couldn't find chat messages in your last screenshots. Screenshot the chat and try again.")
                return
            }
            await generate()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Text the user copied (usually their match's last message or messages).
    func readText(_ copied: String) async {
        let lines = copied
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !BubbleLayout.isChrome($0) }
        guard !lines.isEmpty else {
            phase = .failed("What you copied is empty. Copy their message and try again.")
            return
        }
        replies = []
        messages = [ChatMessage(speaker: .them, text: lines.joined(separator: " "))]
        readCount = 1
        chatID = nil
        latestStart = nil
        replyingTo = nil
        await generate()
    }

    /// A made-up chat for trying the app without a screenshot.
    static let exampleChat = ChatMessage.example

    func tryExample() async {
        replies = []
        messages = Self.exampleChat
        readCount = messages.count
        chatID = nil
        latestStart = nil
        replyingTo = nil
        await generate()
    }

    func generate(tone: ReplyTone? = nil) async {
        guard messages.contains(where: { $0.speaker == .them }) else {
            phase = .failed("Couldn't tell which messages are theirs. Tap a message to switch who said it, then tap Get new replies.")
            return
        }
        phase = .generating
        do {
            replies = try await service.suggestReplies(for: Array(messages.suffix(Self.maxMessagesSent)), platform: "imessage", tone: tone,
                                                       replyingTo: replyingTo)
            editedSinceReplies = false
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func flipSpeaker(of message: ChatMessage) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].speaker = messages[i].speaker.flipped
        editedSinceReplies = true
        saveEdits()
    }

    func delete(at offsets: IndexSet) {
        let removedRead = offsets.filter { $0 >= earlierCount }.count
        messages.remove(atOffsets: offsets)
        readCount = max(readCount - removedRead, 0)
        editedSinceReplies = true
        saveEdits()
    }

    /// Replies the Back Tap shortcut already made.
    func show(_ pending: PendingReplies) {
        messages = pending.messages
        readCount = min(pending.readCount ?? pending.messages.count, pending.messages.count)
        chatID = nil
        latestStart = nil
        replies = pending.replies
        editedSinceReplies = false
        phase = .done
    }

    func reset() {
        previews = []
        phase = .waiting
        messages = []
        replies = []
        readCount = 0
        chatID = nil
        latestStart = nil
        replyingTo = nil
        editedSinceReplies = false
    }
}
