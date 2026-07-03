import SwiftUI

struct SettingsView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("serverKey") private var serverKey = ""

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
                    TextField(ServerConfig.defaultURLString, text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Access key (optional)", text: $serverKey)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Your Wealth server handles bank linking and the cloud advisor. Leave the address empty to use \(ServerConfig.defaultURLString) (Simulator on the same Mac). The access key must match APP_SHARED_SECRET on the server if one is set.")
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
