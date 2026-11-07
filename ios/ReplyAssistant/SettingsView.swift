import SwiftUI
import UIKit
import StoreKit

/// Settings, behind the gear on Home: setup status, your texting style,
/// your plan, privacy.
struct SettingsView: View {
    /// Test builds only: runs first-time setup again.
    var onReplaySetup: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var keyboardOn = KeyboardCheck.isAdded
    @State private var photosOn = RecentScreenshots.hasFullAccess
    @State private var showVoice = false
    @State private var confirmClear = false
    @State private var cleared = false
    @State private var showPaywall = false
    @State private var manageSubscription = false
    @ObservedObject private var purchases = Purchases.shared
    #if DEBUG
    @State private var testPaywall = AccessStore.testPaywall
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    status("Coax keyboard", on: keyboardOn)
                    status("Photos", on: photosOn)
                }

                #if DEBUG
                // Voice profile is a Sprint 3 preview, test builds only.
                Section("You") {
                    Button { showVoice = true } label: {
                        row("Your texting style", detail: VoiceSettings.isEnabled ? "On" : "Off")
                    }
                    .accessibilityIdentifier("voiceProfileButton")
                }
                #endif

                Section("Your plan") {
                    if purchases.access == .subscribed && !AccessStore.isOff {
                        LabeledContent("Coax", value: "Subscribed")
                        Button("Manage subscription") { manageSubscription = true }
                    } else {
                        Button { showPaywall = true } label: {
                            row("See plans", detail: planDetail)
                        }
                        .accessibilityIdentifier("seePlansButton")
                    }
                }

                Section {
                    NavigationLink("What Coax sends") { PrivacyDetail() }
                    if confirmClear {
                        Button("Yes, clear all saved chats", role: .destructive) {
                            ChatStore.shared.forgetAll()
                            confirmClear = false
                            cleared = true
                        }
                        Button("Cancel") { confirmClear = false }
                    } else {
                        Button(cleared ? "Saved chats cleared" : "Clear saved chats", role: .destructive) {
                            confirmClear = true
                        }
                        .disabled(cleared)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Chats are kept on this iPhone for 30 days so replies can use earlier messages.")
                }

                #if DEBUG
                Section {
                    Toggle("Test the paywall", isOn: $testPaywall)
                        .onChange(of: testPaywall) { _, on in
                            AccessStore.testPaywall = on
                            Task { await purchases.refresh() }
                        }
                    if let onReplaySetup {
                        Button("Show setup again") { onReplaySetup() }
                    }
                } header: {
                    Text("Test builds")
                } footer: {
                    Text("Builds from Xcode skip the paywall. Turn this on to use the real free-day rules. Buying here is a free test purchase.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showVoice) { VoiceProfileView() }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .settings) }
            .manageSubscriptionsSheet(isPresented: $manageSubscription)
        }
        .tint(Color.coax)
    }

    private var planDetail: String {
        switch purchases.access {
        case .freeDays(let left): return left == 1 ? "Last free day" : "\(left) free days left"
        case .freeToday(let left): return "\(left) free today"
        case .locked: return "Free days used"
        case .subscribed: return "Free while testing"
        }
    }

    private func status(_ title: String, on: Bool) -> some View {
        Button {
            if !on, let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if on {
                    Label("On", systemImage: "checkmark").foregroundStyle(Color.coaxDone)
                } else {
                    Text("Turn on").foregroundStyle(Color.coax)
                }
            }
        }
        .disabled(on)
    }

    private func row(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct PrivacyDetail: View {
    var body: some View {
        List {
            Section {
                Text("Screenshots are read on your iPhone. Coax never uploads the image.")
                Text("When you ask for replies, only the chat text is sent, to a third-party AI we chose because it never trains on your chats and keeps nothing. No account, and your history stays on your phone.")
                Text("Coax never saves what you type on its keyboard.")
                Text("No account and no analytics. Your chats stay on this iPhone.")
            }
            Section {
                Link("Privacy policy", destination: PaywallView.privacyURL)
                Link("Terms of use", destination: PaywallView.termsURL)
            }
        }
        .navigationTitle("What Coax sends")
    }
}
