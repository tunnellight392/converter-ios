import SwiftUI

/// A simple screen where users type feedback and new conversion requests in-app.
struct FeedbackView: View {
    private static let email = "tunnellightt392@gmail.com"
    private static let subject = "Unit Converter feedback"

    @State private var message = ""
    @State private var alertMessage: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    /// The header emoji's size, scaled with the user's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var emojiSize: CGFloat = 48

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("💬")
                    .font(.system(size: emojiSize))
                    // Decorative: the heading below says the same thing.
                    .accessibilityHidden(true)
                Text("We'd love to hear from you")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Have a suggestion, found a bug, or want a new conversion category added? Type your feedback below and we'll get it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                TextField("Type your feedback or new conversion request here…", text: $message, axis: .vertical)
                    .lineLimit(6...12)
                    .padding(12)
                    .background(Color.cardBackground, in: .rect(cornerRadius: 12))

                Button("Send feedback", systemImage: "paperplane.fill", action: sendFeedback)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding()
        }
        .background(Color.groupedBackground)
        .navigationTitle("Feedback")
        .inlineNavigationTitle()
        .alert(
            alertMessage ?? "",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Open the user's mail app pre-filled with the feedback typed in the app.
    private func sendFeedback() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "Please type some feedback first"
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: Self.subject),
            URLQueryItem(name: "body", value: trimmed)
        ]
        guard let url = components.url else { return }
        openURL(url) { accepted in
            if accepted {
                dismiss()
            } else {
                alertMessage = "No email app found. Please email \(Self.email)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
    }
}
