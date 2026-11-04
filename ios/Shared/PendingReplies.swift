import Foundation
import UIKit

/// Replies made by the Back Tap shortcut, handed to the Coax keyboard.
///
/// The shortcut runs outside the keyboard, so it leaves the replies on the
/// clipboard: the best reply as plain text (ready to paste) plus all of them
/// under a Coax-only type. When the keyboard opens it shows them, so the user
/// only has to tap one. Nothing leaves the phone at this step.
struct PendingReplies: Codable {
    var messages: [ChatMessage]
    var replies: [ReplySuggestion]
    var created: Date
    /// How many of `messages` the screenshot showed (the rest were saved earlier).
    var readCount: Int? = nil

    static let pasteboardType = "com.vchev.coax.replies"
    /// Older replies are ignored: they were probably for another chat.
    static let maxAge: TimeInterval = 15 * 60
    private static let takenKey = "pendingRepliesTaken"

    @MainActor
    static func publish(messages: [ChatMessage], replies: [ReplySuggestion], readCount: Int? = nil) {
        let pending = PendingReplies(messages: messages, replies: replies, created: Date(), readCount: readCount)
        guard let best = replies.first, let data = try? JSONEncoder().encode(pending)
        else { return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": best.text, pasteboardType: data]])
    }

    /// The shortcut's replies, once each, if they're recent. Checking the type
    /// doesn't read the clipboard, so there's no paste banner unless replies are waiting.
    @MainActor
    static func take(now: Date = Date()) -> PendingReplies? {
        let board = UIPasteboard.general
        guard board.contains(pasteboardTypes: [pasteboardType]),
              let data = board.data(forPasteboardType: pasteboardType),
              let pending = try? JSONDecoder().decode(PendingReplies.self, from: data),
              now.timeIntervalSince(pending.created) < maxAge
        else { return nil }
        let stamp = pending.created.timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: takenKey) != stamp else { return nil }
        UserDefaults.standard.set(stamp, forKey: takenKey)
        return pending
    }
}
