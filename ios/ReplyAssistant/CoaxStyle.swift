import SwiftUI

// Building blocks for the app's screens (design direction A, "Clean iOS",
// Nov 5): left-aligned bold titles, one round main button, real chat
// bubbles and the same 1·2·3 reply cards as the keyboard.

/// The main button on a screen: full width, round, Coax blue.
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(Color.coax.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: Capsule())
    }
}

/// A quieter round button with an outline.
struct OutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(minHeight: 52)
            .padding(.horizontal, 18)
            .overlay(Capsule().strokeBorder(Color(.separator)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Plain text button for "Not now", "Later" and similar.
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.coax)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The small "Coax" wordmark.
struct Wordmark: View {
    var size: CGFloat = 20
    var body: some View {
        Text("Coax")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.coax)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A big left-aligned title with an optional line under it.
struct ScreenTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Setup's top bar: back arrow, progress segments, and a skip link.
struct SetupBar: View {
    var step: Int
    var total: Int
    var onBack: (() -> Void)?
    var skipTitle: String?
    var onSkip: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button { onBack?() } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(onBack == nil ? 0 : 1)
            .disabled(onBack == nil)
            .accessibilityLabel("Back")

            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < step ? Color.coax : Color(.systemGray5))
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step) of \(total)")

            if let skipTitle, let onSkip {
                Button(skipTitle, action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A chat bubble drawn like Messages.
struct ChatBubble: View {
    var message: ChatMessage

    var body: some View {
        let mine = message.speaker == .you
        HStack {
            if mine { Spacer(minLength: 48) }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .background(mine ? Color.coax : Color(.systemGray5),
                            in: UnevenRoundedRectangle(topLeadingRadius: 18,
                                                       bottomLeadingRadius: mine ? 18 : 6,
                                                       bottomTrailingRadius: mine ? 6 : 18,
                                                       topTrailingRadius: 18,
                                                       style: .continuous))
            if !mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((mine ? "You: " : "Them: ") + message.text)
    }
}

/// One numbered reply, the same 1·2·3 card the keyboard shows.
struct CoaxReplyCard: View {
    var number: Int
    var reply: ReplySuggestion
    var copied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.coax)
                    .frame(width: 24, height: 24)
                    .background(Color.coaxSoft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(reply.text)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let label = reply.label, !label.isEmpty {
                        Text(label.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.coaxDone : Color.coax)
                    .accessibilityLabel(copied ? "Copied" : "Copy")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(copied ? Color.coaxDone.opacity(0.08) : Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(copied ? Color.coaxDone : Color(.separator)))
        }
        .buttonStyle(.plain)
    }
}

/// A small round tag (tone or mood).
struct TagChip: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
