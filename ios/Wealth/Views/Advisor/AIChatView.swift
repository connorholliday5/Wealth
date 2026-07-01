import SwiftUI
import SwiftData
import FoundationModels

/// On-device advisor chat, powered by Apple Foundation Models (iOS 26+).
@available(iOS 26.0, *)
struct AIChatView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]
    @StateObject private var advisor = AIAdvisorManager()
    @State private var input = ""

    var body: some View {
        Group {
            switch advisor.availability {
            case .available:
                ChatScaffold(
                    messages: advisor.messages,
                    isResponding: advisor.isResponding,
                    input: $input
                ) { text in
                    Task { await advisor.send(text) }
                }
            case .unavailable(let reason):
                ContentUnavailableView(
                    "On-Device AI Unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(message(for: reason))
                )
            @unknown default:
                ContentUnavailableView("On-Device AI Unavailable", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .navigationTitle("On-Device Advisor")
        .onAppear { advisor.start(accounts: accounts, bills: bills) }
    }

    private func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. Use the Cloud advisor instead (Settings → AI Advisor)."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to chat on-device, or use the Cloud advisor."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again shortly."
        @unknown default:
            return "On-device AI isn't available right now. Try the Cloud advisor."
        }
    }
}
