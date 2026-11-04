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

    /// Saved messages from before the latest screenshots.
    var earlierCount: Int { max(messages.count - readCount, 0) }

    /// Keeps what was just read and joins it to the saved chat it belongs to.
    private func use(_ read: [ChatMessage]) {
        readCount = read.count
        guard let store, !read.isEmpty else {
            messages = read
            chatID = nil
            return
        }
        let chat = store.remember(read, key: chatKey)
        chatID = chat.id
        messages = chat.messages
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
            let images = try await RecentScreenshots.latest(min(max(count, 1), 3))
            previews = images
            var parts: [[ChatMessage]] = []
            replyingTo = nil
            for image in images {   // oldest first, so the newest bar wins
                let chat = try await reader.readChat(image)
                parts.append(chat.messages)
                replyingTo = chat.replyingTo ?? replyingTo
            }
            let all = Transcript.joinBestOrder(parts)
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
        replyingTo = nil
        await generate()
    }

    /// A made-up chat for trying the app without a screenshot.
    static let exampleChat: [ChatMessage] = [
        ChatMessage(speaker: .them, text: "ok your third photo, is that a pottery wheel??"),
        ChatMessage(speaker: .you, text: "guilty. I took one class and now I think I'm a ceramicist"),
        ChatMessage(speaker: .them, text: "haha that's amazing. what did you make"),
        ChatMessage(speaker: .you, text: "a bowl that is technically also a plate"),
        ChatMessage(speaker: .them, text: "honestly iconic. are you free this weekend? I want to see this bowl-plate"),
    ]

    func tryExample() async {
        replies = []
        messages = Self.exampleChat
        readCount = messages.count
        chatID = nil
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
        replyingTo = nil
        editedSinceReplies = false
    }
}
