import SwiftUI
import StoreKit

/// The paywall, direction C (Vanessa, Nov 7): it slides up over the chat that was
/// just read and goes straight to its 3 replies once someone subscribes. From
/// Settings it opens on its own, without a chat.
///
/// Weekly is listed first and both plans are shown per week, with yearly picked
/// (Vanessa: lead with the lower price). Apple's required parts are all here:
/// price per period, the auto-renew line, Restore, Terms and Privacy.
struct PaywallView: View {
    enum Context { case chat, settings }

    var context: Context
    /// Why replies stopped, when opened from a chat.
    var lock: AccessLock?
    /// Called after a successful purchase or restore (the sheet is already closing).
    var onUnlocked: () -> Void = {}

    @ObservedObject private var purchases = Purchases.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pickedYearly = true
    @State private var trials: [String: String] = [:]   // product id -> "7-day"
    @State private var restoring = false
    @State private var didUnlock = false

    static let termsURL = URL(string: "https://hicoax.com/terms/")!
    static let privacyURL = URL(string: "https://hicoax.com/privacy/")!

    private var weekly: Product? { purchases.products.first { $0.id == Entitlements.weeklyID } }
    private var yearly: Product? { purchases.products.first { $0.id == Entitlements.yearlyID } }
    private var picked: Product? { pickedYearly ? yearly : weekly }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(headline)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(subhead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if context == .settings { benefits }
                plans
                buyButton
                if let problem = purchases.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Not now") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paywallNotNow")
                finePrint
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .tint(Color.coax)
        .task {
            if purchases.products.isEmpty { await purchases.loadProducts() }
            await loadTrials()
        }
        .onChange(of: purchases.access) { _, access in
            if access == .subscribed { unlocked() }
        }
    }

    // MARK: Words

    private var headline: String {
        context == .chat ? "Your screenshot is in. Unlock to get your 3 replies."
                         : "Keep getting replies that sound like you"
    }

    private var subhead: String {
        switch lock ?? purchases.access.lock {
        case .freeDaysOver:
            return "Your \(AccessPolicy.freeDays) free days are up. Coax already knows how you text."
        case .dailyLimitReached:
            return "That's today's \(AccessPolicy.freeChatsPerDay) free chats. Go unlimited, or come back tomorrow."
        case nil:
            switch purchases.access {
            case .freeDays(let left): return left == 1 ? "Your last free day." : "\(left) free days left."
            case .freeToday(let left): return "\(left) free chat\(left == 1 ? "" : "s") left today."
            default: return "Unlimited chats, every match."
            }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Unlimited chats, every match", systemImage: "checkmark")
            Label("Replies in your texting type", systemImage: "checkmark")
            Label("Your chats stay on your phone", systemImage: "checkmark")
        }
        .font(.subheadline)
        .labelStyle(CheckLabel())
    }

    // MARK: Plans

    @ViewBuilder private var plans: some View {
        if let weekly, let yearly {
            VStack(spacing: 8) {
                Picker("Plan", selection: $pickedYearly) {
                    Text("Weekly · \(weekly.displayPrice)/wk").tag(false)
                    Text("Yearly · \(perWeek(yearly))/wk").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("paywallPlan")
                Text(planLine(weekly: weekly, yearly: yearly))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Getting prices from the App Store…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func perWeek(_ yearly: Product) -> String {
        PlanPricing.perWeek(yearly: yearly.price).formatted(yearly.priceFormatStyle)
    }

    private func planLine(weekly: Product, yearly: Product) -> String {
        var parts: [String]
        if pickedYearly {
            parts = ["\(yearly.displayPrice) billed yearly"]
            let saving = PlanPricing.savingPercent(weekly: weekly.price, yearly: yearly.price)
            if saving > 0 { parts.append("save \(saving)%") }
        } else {
            parts = ["\(weekly.displayPrice) billed weekly"]
        }
        if let picked, let trial = trials[picked.id] { parts.append("\(trial == "7-day" ? "7 days" : trial) free") }
        return parts.joined(separator: " · ")
    }

    private var buyButton: some View {
        Button {
            guard let picked else { return }
            Task { if await purchases.buy(picked) { unlocked() } }
        } label: {
            HStack(spacing: 8) {
                if purchases.isBuying { ProgressView().tint(.white) }
                Text(buyTitle)
            }
        }
        .buttonStyle(PrimaryButton())
        .disabled(picked == nil || purchases.isBuying || restoring)
        .accessibilityIdentifier("paywallBuy")
    }

    private var buyTitle: String {
        let trial = picked.flatMap { trials[$0.id] }
        switch (context, trial) {
        case (.chat, .some): return "Start free trial and see replies"
        case (.chat, .none): return "Subscribe and see replies"
        case (.settings, .some(let length)): return "Start \(length) free trial"
        case (.settings, .none): return "Subscribe"
        }
    }

    // MARK: Fine print (Apple's required parts)

    private var finePrint: some View {
        VStack(spacing: 10) {
            Text(renewalLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button(restoring ? "Restoring…" : "Restore") {
                    restoring = true
                    Task {
                        await purchases.restore()
                        restoring = false
                        if purchases.access == .subscribed { unlocked() }
                    }
                }
                .disabled(restoring || purchases.isBuying)
                Link("Terms", destination: Self.termsURL)
                Link("Privacy", destination: Self.privacyURL)
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var renewalLine: String {
        guard let picked else { return "Subscriptions renew automatically until you cancel." }
        let period = picked.id == Entitlements.yearlyID ? "a year" : "a week"
        let start = trials[picked.id].map { "Free for \($0 == "7-day" ? "7 days" : $0), then \(picked.displayPrice) \(period)." }
            ?? "\(picked.displayPrice) \(period)."
        return start + " Renews automatically until you cancel. Cancel anytime in Settings at least 24 hours before it renews."
    }

    // MARK: Actions

    private func loadTrials() async {
        var found: [String: String] = [:]
        for product in purchases.products {
            guard await purchases.hasFreeTrial(product) else { continue }
            guard let period = product.subscription?.introductoryOffer?.period else { continue }
            let unit: PlanPricing.TrialUnit
            switch period.unit {
            case .day: unit = .day
            case .week: unit = .week
            case .month: unit = .month
            case .year: unit = .year
            @unknown default: unit = .day
            }
            found[product.id] = PlanPricing.trialLength(value: period.value, unit: unit)
        }
        trials = found
    }

    private func unlocked() {
        guard !didUnlock else { return }
        didUnlock = true
        dismiss()
        onUnlocked()
    }
}

/// A coloured checkmark in front of each benefit.
private struct CheckLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(Color.coax).fontWeight(.bold)
            configuration.title
        }
    }
}
