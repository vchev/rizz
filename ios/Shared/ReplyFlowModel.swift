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

    let service: ReplyService
    private let reader = ScreenshotReader()

    init(service: ReplyService = ReplyServices.makeDefault()) {
        self.service = service
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
            for image in images {
                all = Transcript.append(try await reader.read(image), to: all)
            }
            messages = all
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
        do {
            let images = try await RecentScreenshots.latest(min(max(count, 1), 3))
            var parts: [[ChatMessage]] = []
            for image in images {
                parts.append(try await reader.read(image))
            }
            let all = Transcript.joinBestOrder(parts)
            messages = all
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
        await generate()
    }

    func generate(tone: ReplyTone? = nil) async {
        guard messages.contains(where: { $0.speaker == .them }) else {
            phase = .failed("Couldn't tell which messages are theirs. Tap a message to switch who said it, then tap Get new replies.")
            return
        }
        phase = .generating
        do {
            replies = try await service.suggestReplies(for: messages, platform: "imessage", tone: tone)
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
    }

    func delete(at offsets: IndexSet) {
        messages.remove(atOffsets: offsets)
        editedSinceReplies = true
    }

    func reset() {
        phase = .waiting
        messages = []
        replies = []
        editedSinceReplies = false
    }
}
