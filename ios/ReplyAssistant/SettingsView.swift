import SwiftUI
import UIKit

/// Settings, behind the gear on Home: setup status, your texting style,
/// privacy. The plan (Sprint 4) slots in here later.
struct SettingsView: View {
    /// Test builds only: runs first-time setup again.
    var onReplaySetup: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var keyboardOn = KeyboardCheck.isAdded
    @State private var photosOn = RecentScreenshots.hasAccess
    @State private var showVoice = false
    @State private var confirmClear = false
    @State private var cleared = false

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
                if let onReplaySetup {
                    Section("Test builds") {
                        Button("Show setup again") { onReplaySetup() }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showVoice) { VoiceProfileView() }
        }
        .tint(Color.coax)
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
                Text("When you ask for replies, only the chat text goes to Claude, made by Anthropic, to write them. It isn't kept.")
                Text("Coax never saves what you type on its keyboard.")
                Text("No account and no analytics. Your chats stay on this iPhone.")
            }
        }
        .navigationTitle("What Coax sends")
    }
}
