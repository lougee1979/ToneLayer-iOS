// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import ToneLayerCore

/// Opens once a rewrite has already failed 2 refine attempts — instead of
/// another single-shot correction box, this is a real back-and-forth with
/// the Companion until the user is satisfied. The user decides when a
/// reply is actually the right rewrite by tapping "Use this" on it; there's
/// no automatic detection of "correct."
struct EscalationConversationView: View {
    let originalText: String
    let currentRewrite: String
    let profile: String

    /// Called when the user accepts a reply as the final rewrite, with the
    /// full conversation so far (including the accepted reply) so the
    /// caller can scrub + offer it for review/export.
    let onAccept: (_ finalText: String, _ transcript: [CompanionMessage]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [CompanionMessage]
    @State private var draftReply = ""
    @State private var isSending = false
    @State private var errorText = ""

    private let client = CompanionClient()

    private static let openingLine = "This one's tricky \u{2014} what part of this isn't landing the way you want it to?"

    init(originalText: String, currentRewrite: String, profile: String,
         onAccept: @escaping (_ finalText: String, _ transcript: [CompanionMessage]) -> Void,
         onCancel: @escaping () -> Void) {
        self.originalText = originalText
        self.currentRewrite = currentRewrite
        self.profile = profile
        self.onAccept = onAccept
        self.onCancel = onCancel
        _messages = State(initialValue: [CompanionMessage(role: .assistant, content: Self.openingLine)])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                bubble(message, showUseThis: message.role == .assistant && index > 0)
                                    .id(message.id)
                            }
                            if isSending {
                                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                Divider()
                HStack(spacing: 10) {
                    TextField("Type your reply\u{2026}", text: $draftReply)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.brandVioletDark)
                    }
                    .disabled(isSending || draftReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Let's work this out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func bubble(_ message: CompanionMessage, showUseThis: Bool) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.content)
                .font(.subheadline)
                .padding(10)
                .background(message.role == .user ? Color.brandVioletDark.opacity(0.85) : Color.brandVioletMist)
                .foregroundStyle(message.role == .user ? .white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if showUseThis {
                Button("Use this") { accept(text: message.content) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func accept(text: String) {
        onAccept(text, messages)
        dismiss()
    }

    private func send() {
        let reply = draftReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty, !isSending else { return }
        draftReply = ""
        errorText = ""
        let historyBeforeReply = messages
        messages.append(CompanionMessage(role: .user, content: reply))
        isSending = true
        Task {
            do {
                let context = "Original message: \(originalText)\n\nCurrent rewrite that isn't quite right: \(currentRewrite)"
                let result = try await client.send(
                    history: historyBeforeReply,
                    newUserMessage: reply,
                    rewriteContext: context,
                    profile: profile
                )
                await MainActor.run {
                    messages.append(CompanionMessage(role: .assistant, content: result.reply))
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
