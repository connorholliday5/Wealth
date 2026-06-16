import SwiftUI
import SwiftData
import FoundationModels

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
                chatBody
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
        .navigationTitle("Ask the Advisor")
        .onAppear { advisor.start(accounts: accounts, bills: bills) }
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(advisor.messages) { message in
                        ChatBubble(message: message)
                    }
                    if advisor.isResponding {
                        ProgressView().padding(.leading)
                    }
                }
                .padding()
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Ask about your finances...", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = input
                    input = ""
                    Task { await advisor.send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || advisor.isResponding)
            }
            .padding()
        }
    }

    private func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to chat with the on-device advisor."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again shortly."
        @unknown default:
            return "On-device AI isn't available right now."
        }
    }
}

@available(iOS 26.0, *)
private struct ChatBubble: View {
    let message: AIAdvisorManager.ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 0) }
            Text(message.text)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.role == .advisor { Spacer(minLength: 0) }
        }
    }
}
