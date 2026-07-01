import SwiftUI

struct SettingsView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Require Face ID / Passcode", isOn: $appLockEnabled)
                } header: {
                    Text("Security")
                } footer: {
                    Text("When on, Wealth locks whenever you leave the app and requires Face ID, Touch ID, or your device passcode before showing balances.")
                }

                Section {
                    NavigationLink {
                        AdvisorSettingsView()
                    } label: {
                        Label("AI Advisor", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Choose how the conversational advisor runs — on-device (Apple Intelligence) or via a cloud model through your Wealth server.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
