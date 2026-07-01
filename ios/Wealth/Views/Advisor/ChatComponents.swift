import SwiftUI

/// One chat bubble, shared by the on-device and cloud advisor chat views.
struct ChatBubble: View {
    let message: AdvisorMessage

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

/// Scrolling transcript + input bar, shared by both chat backends. The parent
/// owns the message list and the send action; this view is pure presentation.
struct ChatScaffold: View {
    let messages: [AdvisorMessage]
    let isResponding: Bool
    @Binding var input: String
    let onSend: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                    }
                    if isResponding {
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
                    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    input = ""
                    onSend(text)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
            }
            .padding()
        }
    }
}
