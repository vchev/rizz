import Foundation
import StoreKit

/// Buying and restoring the Coax subscription (StoreKit 2), for the paywall screen.
///
/// Prices: $4.99/week or $99/year, no monthly (Nov 3 decision). Both start with
/// Apple's 7-day free trial, set up as an introductory offer in App Store Connect.
/// Price tests later use extra product IDs in this same app (one app, Apple 4.3).
///
/// Until the products exist in App Store Connect (needs the paid developer account),
/// running from Xcode uses ios/Coax.storekit, so the paywall can be tried for free.
@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    /// Weekly first, then yearly. Empty until loaded (or when the App Store can't be reached).
    @Published private(set) var products: [Product] = []
    @Published private(set) var access: AccessState = AccessStore.state()
    @Published private(set) var isBuying = false
    /// Plain words when buying or restoring failed; nil otherwise.
    @Published var problem: String?

    private var updates: Task<Void, Never>?

    private init() {}

    /// Call once at app launch: loads prices, reads the subscription, and
    /// listens for renewals, refunds and purchases made elsewhere.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Entitlements.productIDs)
            products = Entitlements.productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            products = []
        }
    }

    func refresh() async {
        await Entitlements.refresh()
        access = AccessStore.state()
    }

    /// Returns true when the person is now subscribed.
    @discardableResult
    func buy(_ product: Product) async -> Bool {
        isBuying = true
        problem = nil
        defer { isBuying = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result else {
                    problem = "Apple couldn't confirm that purchase. Try again, or tap Restore."
                    return false
                }
                await t.finish()
                await refresh()
                return access == .subscribed
            case .pending:
                problem = "Your purchase is waiting for approval. Coax unlocks as soon as it goes through."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            problem = "The App Store didn't respond. Check your connection and try again."
            return false
        }
    }

    /// "Restore purchases": asks Apple for this Apple ID's subscriptions.
    func restore() async {
        problem = nil
        do {
            try await AppStore.sync()
        } catch {
            problem = "Couldn't reach the App Store to restore. Try again in a moment."
        }
        await refresh()
        if access != .subscribed && problem == nil {
            problem = "No Coax subscription found for this Apple ID."
        }
    }

    /// Whether the product starts with a free trial this person can still use.
    func hasFreeTrial(_ product: Product) async -> Bool {
        guard let sub = product.subscription, sub.introductoryOffer?.paymentMode == .freeTrial else { return false }
        return await sub.isEligibleForIntroOffer
    }
}
