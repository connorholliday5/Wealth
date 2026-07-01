import SwiftUI

struct AdvisorSettingsView: View {
    @AppStorage("advisorProvider") private var providerRaw = AdvisorProvider.auto.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Advisor Model", selection: $providerRaw) {
                    ForEach(AdvisorProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Automatic uses Apple's on-device model when your iPhone supports it, and falls back to the cloud model otherwise. On-device is free and fully private. Cloud works on any iPhone but sends a snapshot of your accounts and bills to the model through your Wealth server, and may incur usage costs on your API key.")
            }
        }
        .navigationTitle("AI Advisor")
    }
}

#Preview {
    NavigationStack { AdvisorSettingsView() }
}
