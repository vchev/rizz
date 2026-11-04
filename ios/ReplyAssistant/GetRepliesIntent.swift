import AppIntents
import UIKit
import UniformTypeIdentifiers

/// A Shortcuts action: screenshot or text in, replies out, best reply copied.
/// Lets people keep a Back Tap / Action button shortcut and swap in Coax.
struct GetCoaxRepliesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Coax Replies"
    static var description = IntentDescription(
        "Reads a chat screenshot (on your phone) or some text, suggests replies, and copies the best one.")
    static var openAppWhenRun = false

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile?

    @Parameter(title: "Text")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Get Coax replies for \(\.$screenshot)") {
            \.$text
        }
    }

    struct NothingToReadError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Coax couldn't find their messages. Pass in a screenshot of the chat, or the text of their message."
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var messages: [ChatMessage] = []
        var replyingTo: String?
        if let data = screenshot?.data, let image = UIImage(data: data) {
            let chat = try await ScreenshotReader().readChat(image)
            messages = chat.messages
            replyingTo = chat.replyingTo
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages = [ChatMessage(speaker: .them, text: text)]
        }
        guard messages.contains(where: { $0.speaker == .them }) else { throw NothingToReadError() }

        // Add the earlier part of this chat, if Coax has read it before.
        let readCount = messages.count
        if screenshot != nil, let store = ChatStore.forUse {
            messages = Array(store.remember(messages).messages.suffix(ReplyFlowModel.maxMessagesSent))
        }

        let replies = try await ReplyServices.makeDefault()
            .suggestReplies(for: messages, platform: "imessage", tone: nil, replyingTo: replyingTo)
        guard let best = replies.first else { throw NothingToReadError() }

        // Best reply on the clipboard, and all of them waiting in the Coax keyboard.
        await PendingReplies.publish(messages: messages, replies: replies, readCount: readCount)

        let summary = "\(replies.count) replies are waiting in the Coax keyboard. Tap the message box to pick one."
        return .result(value: best.text, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct CoaxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetCoaxRepliesIntent(),
                    phrases: ["Get replies with \(.applicationName)"],
                    shortTitle: "Get Replies",
                    systemImageName: "sparkles")
    }
}
