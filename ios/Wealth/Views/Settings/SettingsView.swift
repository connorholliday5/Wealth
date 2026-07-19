import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("serverURL") private var serverURL = ""

    // Access key lives in the Keychain, not @AppStorage. Mirror it into local
    // @State for editing and write changes back through ServerConfig.
    @State private var serverKey = ""

    @State private var exportURLs: [URL] = []
    @State private var isSharing = false
    @State private var exportError: String?

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
                    Text("Your Wealth server handles bank linking and the cloud advisor. Leave the address empty to use \(ServerConfig.defaultURLString) (Simulator on the same Mac). The access key must match APP_SHARED_SECRET on the server if one is set. The key is stored securely in the device Keychain.")
                }

                Section {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export Backup (JSON)", systemImage: "arrow.down.doc")
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text("Export everything you've entered. CSV gives spreadsheet-friendly files for accounts, transactions and bills. The JSON backup captures every field for safekeeping.")
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
            .onAppear {
                serverKey = ServerConfig.accessKey
            }
            .onChange(of: serverKey) { _, newValue in
                ServerConfig.setAccessKey(newValue)
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(items: exportURLs)
            }
            .alert("Export failed", isPresented: exportErrorBinding) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func exportCSV() {
        do {
            exportURLs = try DataExporter.csvExports(context: modelContext)
            isSharing = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            exportURLs = [try DataExporter.jsonBackup(context: modelContext)]
            isSharing = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Thin wrapper around UIActivityViewController so exported file URLs can be
/// shared (AirDrop, Files, Mail, …) from a SwiftUI sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
