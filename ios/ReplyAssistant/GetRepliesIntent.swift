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

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
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
        if let data = screenshot?.data, let image = UIImage(data: data) {
            messages = try await ScreenshotReader().read(image)
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages = [ChatMessage(speaker: .them, text: text)]
        }
        guard messages.contains(where: { $0.speaker == .them }) else { throw NothingToReadError() }

        let replies = try await ReplyServices.makeDefault()
            .suggestReplies(for: messages, platform: "imessage", tone: nil)
        guard let best = replies.first else { throw NothingToReadError() }

        await MainActor.run { UIPasteboard.general.string = best.text }

        let others = replies.dropFirst().map { "• \($0.text)" }.joined(separator: "\n")
        let summary = others.isEmpty ? "Copied: \(best.text)" : "Copied: \(best.text)\n\nOther ideas:\n\(others)"
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
