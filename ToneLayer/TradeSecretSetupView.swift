// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import ToneLayerCore

/// Shown once, right after the agreement is accepted and before the user
/// reaches the main app — the app's other redaction categories (names,
/// phone numbers, bank details, crypto keys) are all pattern-detectable
/// automatically, but trade secrets and business-confidential terms aren't:
/// there's no shape to detect, only whatever the user tells the app to
/// always strip. Asking for this list up front, before any real message
/// gets typed, means the very first message is already protected instead
/// of leaving a gap until the user happens to find this in Settings.
struct TradeSecretSetupView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.918, green: 0.898, blue: 0.984), Color(red: 0.749, green: 0.820, blue: 0.996)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(red: 0.369, green: 0.122, blue: 0.784))
                    Text("Protect Business Terms").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 0.220, green: 0.122, blue: 0.584))
                        .multilineTextAlignment(.center)
                    Text("Optional \u{2014} but worth a minute before you start typing")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.top, 44).padding(.bottom, 16)
                .padding(.horizontal, 24)

                Text("ToneLayer automatically strips names, phone numbers, addresses, and financial details before anything leaves your phone. But it can't guess a client name, project codename, or trade secret \u{2014} only you know those. Add any words you never want sent to any AI, and they'll be stripped the same way, every time.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.22))
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                ScrollView {
                    CustomTermsEditorCard()
                        .padding(.horizontal, 20)
                }

                Button {
                    CustomTermsStore.hasSeenSetup = true
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.369, green: 0.122, blue: 0.784))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
    }
}

/// The actual add/remove list — factored out so it can be embedded both in
/// the one-time setup screen above and as an editable card in Settings
/// (people's client rosters and projects change; this shouldn't be a
/// one-shot decision only visible during onboarding).
struct CustomTermsEditorCard: View {
    @State private var terms: [String] = CustomTermsStore.terms
    @State private var newTerm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Business & Trade-Secret Terms", systemImage: "briefcase.fill")
                .font(.title3.weight(.semibold))
            Text("Any word or phrase here gets redacted from every message before it's sent \u{2014} same protection as the app's built-in categories.")
                .foregroundStyle(.secondary).font(.subheadline)

            HStack(spacing: 10) {
                TextField("e.g. Project Kestrel, Acme Corp", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(addTerm)
                Button(action: addTerm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(newTerm.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.brandVioletDark)
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if terms.isEmpty {
                Text("No terms added yet. That's fine \u{2014} you can always add some later in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(terms, id: \.self) { term in
                        HStack {
                            Text(term).font(.subheadline)
                            Spacer()
                            Button {
                                remove(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Remove \(term)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newTerm = ""
            return
        }
        terms.append(trimmed)
        CustomTermsStore.terms = terms
        newTerm = ""
    }

    private func remove(_ term: String) {
        terms.removeAll { $0 == term }
        CustomTermsStore.terms = terms
    }
}
