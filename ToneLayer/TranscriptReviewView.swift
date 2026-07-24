// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import ToneLayerCore

/// Shown once, right after an escalation conversation (see
/// `EscalationConversationView`) ends in an accepted rewrite — never for
/// ordinary rewrites/refines, which are never logged or offered for export.
/// The user always gets the final say on whether this leaves the device:
/// the redacted transcript is editable so they can strike anything the
/// automatic pass missed, and nothing sends until they explicitly approve.
struct TranscriptReviewView: View {
    let transcript: [CompanionMessage]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appModel: AppModel

    @State private var editableText = ""
    @State private var noticeText: String?

    private let redactor = PIIRedactor()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("This is what would be sent — personal details have already been replaced with placeholders. Edit anything below before sending, or don't send at all.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let noticeText {
                    Text(noticeText)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.0))
                }
                TextEditor(text: $editableText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Don't send").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        appModel.activityItems = [editableText]
                        appModel.showingExportSheet = true
                        dismiss()
                    } label: {
                        Text("Send").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandVioletDark)
                    .disabled(editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .navigationTitle("Review before sending")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: prepareRedactedTranscript)
        }
    }

    private func prepareRedactedTranscript() {
        let (redactedContents, _, flaggedKinds) = redactor.redactMultiple(transcript.map(\.content))
        let lines = zip(transcript, redactedContents).map { message, redacted in
            "\(message.role == .user ? "You" : "ToneLayer"): \(redacted)"
        }
        editableText = lines.joined(separator: "\n\n")
        noticeText = PIIRedactor.friendlyNotice(for: flaggedKinds)
    }
}
