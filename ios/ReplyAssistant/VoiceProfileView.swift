import SwiftUI

/// "Your texting style" (Sprint 3 preview): a one-question-per-screen quiz, then a style card
/// that keeps improving from the user's own messages in their screenshots.
/// Reached from the main screen in test builds only.
struct VoiceProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile = VoiceSettings.profile
    @State private var takingQuiz = !VoiceSettings.profile.hasQuiz
    @State private var answers: [String: Double] = {
        let saved = VoiceSettings.profile.quiz
        return saved.isEmpty ? Dictionary(uniqueKeysWithValues: VoiceTrait.allCases.map { ($0.rawValue, 0.5) }) : saved
    }()
    @State private var step = 0
    @State private var enabled = VoiceSettings.isEnabled
    @State private var learning = VoiceSettings.isLearning

    var body: some View {
        NavigationStack {
            Group {
                if takingQuiz { quiz } else { card }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(takingQuiz && profile.hasQuiz ? "Cancel" : "Done") {
                        if takingQuiz && profile.hasQuiz { takingQuiz = false } else { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: Quiz

    /// One question per screen with a progress bar; the style card is the result.
    private var quiz: some View {
        let traits = VoiceTrait.allCases
        let trait = traits[min(step, traits.count - 1)]
        let isLast = step >= traits.count - 1
        return VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: Double(step + 1), total: Double(traits.count))
                .tint(Color.coax)
            HStack {
                Text("Question \(step + 1) of \(traits.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                }
            }
            Text(step == 0 ? "How do you text? Coax keeps learning from the screenshots you take." : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(trait.question)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .id(trait)
                .transition(.opacity)
            VStack(spacing: 8) {
                Slider(value: binding(trait), in: 0...1)
                    .tint(Color.coax)
                    .accessibilityLabel(trait.question)
                    .accessibilityValue(describe(trait, answers[trait.rawValue] ?? 0.5))
                HStack {
                    Text(trait.ends.low)
                    Spacer()
                    Text(trait.ends.high)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 0)
            Button {
                if isLast { finishQuiz() } else { withAnimation { step += 1 } }
            } label: {
                Text(isLast ? "See my style" : "Next").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.coax)
            .controlSize(.large)
            .accessibilityIdentifier("voiceQuizNext")
        }
        .padding(22)
    }

    private func finishQuiz() {
        var updated = VoiceSettings.profile
        updated.quiz = answers
        updated.trustQuiz = false
        save(updated)
        VoiceSettings.isEnabled = true
        enabled = true
        step = 0
        takingQuiz = false
    }

    private func binding(_ trait: VoiceTrait) -> Binding<Double> {
        Binding(get: { answers[trait.rawValue] ?? 0.5 }, set: { answers[trait.rawValue] = $0 })
    }

    private func describe(_ trait: VoiceTrait, _ value: Double) -> String {
        value < 0.4 ? trait.ends.low : value > 0.6 ? trait.ends.high : "in between"
    }

    // MARK: Style card

    private var card: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(profile.surprise == nil ? "YOUR TEXTING STYLE" : "YOUR TEXTING STYLE · UPDATED")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(profile.surprise ?? profile.headline)
                        .font(.title2.bold())
                    if !profile.chips.isEmpty {
                        ChipRow(chips: profile.chips)
                    }
                    // Every scale shows; ones Coax hasn't learned yet say so, so the learning is visible.
                    ForEach(VoiceTrait.allCases) { trait in
                        TraitScale(trait: trait,
                                   value: profile.shownTraits.contains(trait) ? profile.value(trait) : nil,
                                   quizValue: profile.surprise != nil ? profile.quiz[trait.rawValue] : nil)
                    }
                    if profile.surprise != nil {
                        HStack(spacing: 10) {
                            Button("Keep it") {
                                var updated = profile
                                updated.acceptLearned()
                                save(updated)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Go back to my quiz") {
                                var updated = profile
                                updated.trustQuiz = true
                                save(updated)
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.large)
                    }
                }
                .padding(.vertical, 6)
                ShareLink(item: profile.shareText) {
                    Label("Share my style", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                if !profile.recent.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(profile.recent.suffix(3), id: \.self) { text in
                            Text(text)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                LabeledContent("Your own texts read", value: messagesLine)
                Button("Retake the quiz") { step = 0; takingQuiz = true }
            } header: {
                Text("Learned from")
            } footer: {
                Text(profile.messageCount < VoiceProfile.confidentAt
                     ? "Still learning: about \(Int(VoiceProfile.messagesForFullWeight)) of your own texts make a full profile. Coax picks them up from the screenshots you already take for replies. Nothing extra to do."
                     : "Your own messages in the screenshots you take for replies keep this up to date.")
            }

            Section {
                Toggle("Use my voice in replies", isOn: $enabled)
                    .onChange(of: enabled) { _, on in VoiceSettings.isEnabled = on }
                Toggle("Learn from what I send", isOn: $learning)
                    .onChange(of: learning) { _, on in VoiceSettings.isLearning = on }
            } footer: {
                Text("Your voice stays on this phone. Each reply sends a short style summary and a few of your own texts with the chat, and none of it is kept.")
            }

            Section {
                Button("Reset my voice", role: .destructive) {
                    VoiceSettings.reset()
                    profile = VoiceProfile()
                    answers = Dictionary(uniqueKeysWithValues: VoiceTrait.allCases.map { ($0.rawValue, 0.5) })
                    enabled = false
                    learning = true
                    takingQuiz = true
                }
            }
        }
    }

    private var messagesLine: String {
        // Your own texts (not screenshots), counted once each. 40 = a full profile.
        let full = Int(VoiceProfile.messagesForFullWeight)
        return profile.messageCount >= full ? "\(profile.messageCount) · full profile" : "\(profile.messageCount) of \(full)"
    }

    private func save(_ updated: VoiceProfile) {
        VoiceSettings.profile = updated
        profile = updated
    }
}

extension VoiceProfile {
    var shareText: String {
        "My texting style: \(headline.lowercased()). " + chips.joined(separator: ", ") + ". Found by Coax, replies that sound like you."
    }
}

/// One slider shown read-only, with an optional hollow marker for the quiz answer.
private struct TraitScale: View {
    var trait: VoiceTrait
    /// nil = not learned yet: the track shows "learning from your texts" instead of a dot.
    var value: Double?
    var quizValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trait.name)
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(trait.ends.low)
                Spacer()
                Text(trait.ends.high)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    if let quizValue {
                        Circle()
                            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                            .frame(width: 16, height: 16)
                            .offset(x: quizValue * (geo.size.width - 16))
                    }
                    if let value {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 18, height: 18)
                            .offset(x: value * (geo.size.width - 18))
                    } else {
                        Text("Learning from your texts…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trait.name)
        .accessibilityValue(value.map { $0 < 0.4 ? trait.ends.low : $0 > 0.6 ? trait.ends.high : "in between" } ?? "still learning")
    }
}

/// Chips that wrap onto new lines.
private struct ChipRow: View {
    var chips: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
