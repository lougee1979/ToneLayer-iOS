// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import UIKit

struct ComposerView: View {

    @EnvironmentObject var appModel: AppModel

    @State private var isComposerRewriting = false
    @State private var composerStatus      = ""
    @State private var composerOriginal    = ""
    @State private var composerGrammar     = ""
    @State private var composerNT          = ""
    @State private var composerExplanation = ""
    @State private var selectedOutput      = "NT version"
    @State private var feedbackSubmitted   = false
    @State private var showingInsight      = false

    private let outputTabs = ["Original", "Grammar only", "NT version"]

    private let dailyTips: [(title: String, body: String)] = [
        (
            "RSD can make silence feel personal",
            "Rejection sensitivity is common for many people with ADHD. A delayed reply, a blocked call, or a short message can feel like proof that something is wrong, even when the other person is only busy or overwhelmed."
        ),
        (
            "Direct does not mean rude",
            "Many neurodivergent people communicate best with clear, specific language. A direct request can reduce guessing, anxiety, and the pressure to decode hidden meaning."
        ),
        (
            "Too many options can freeze action",
            "When everything feels equally urgent, the brain may stall instead of choosing. Naming one next step can be more helpful than giving a full list of possible solutions."
        ),
        (
            "Tone can get lost in text",
            "Short messages can be read as anger or rejection when the nervous system is already activated. Adding one warm sentence can change how safe the message feels."
        ),
        (
            "Body doubling is practical support",
            "Some people start tasks more easily when another person is present or checking in. It is not dependence; it can be a way to borrow structure long enough to begin."
        ),
        (
            "Clarity lowers the social load",
            "A message that says what happened, what is needed, and when a reply is expected gives the other person fewer hidden steps to interpret."
        ),
        (
            "Overexplaining can be a safety behavior",
            "A long message may be an attempt to prevent misunderstanding, criticism, or rejection. The goal is not to remove the person's voice, but to organize it so the need is clear."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                dailyTipCard
                composerCard
                insightCard
                teachingCard
            }
            .padding()
        }
        .appBackground()
        .sheet(isPresented: $showingInsight) {
            InsightView(onUseTranscript: { text in
                appModel.testText = text
                appModel.sharedDefaults.set(appModel.testText, forKey: "testBoxFullText")
                appModel.sharedDefaults.synchronize()
                composerStatus = "Used TonalInsight transcript"
            }, onLiveTranscriptUpdate: { text in
                appModel.testText = text
                appModel.sharedDefaults.set(appModel.testText, forKey: "testBoxFullText")
                appModel.sharedDefaults.synchronize()
            })
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image("ToneLayerLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("ToneLayer")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.brandGreen)
            Text("Write it out your way. ToneLayer translates it into NT-readable communication.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(tint: .brandGreen)
    }

    private var dailyTipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FYI of the day", systemImage: "sparkle.magnifyingglass")
                .font(.headline)
                .foregroundStyle(Color.brandVioletDark)
            Text(todayTip.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(todayTip.body)
                .font(.subheadline)
                .foregroundStyle(Color(red: 0.22, green: 0.26, blue: 0.30))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(tint: .brandViolet, cornerRadius: 18)
    }

    private var todayTip: (title: String, body: String) {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dailyTips[(day - 1) % dailyTips.count]
    }

    private var insightCard: some View {
        Button {
            showingInsight = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.brandVioletDark)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TonalInsight\u{2122} (Beta)")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Talk it through \u{2014} ToneLayer listens to your tone of voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(tint: .brandViolet, cornerRadius: 18)
    }

    private var teachingCard: some View {
        Group {
            if appModel.showExplanation {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How this lands", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(Color.brandVioletDark)
                    if hasComposerOutput && !composerExplanation.isEmpty {
                        Text(composerExplanation)
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if hasComposerOutput {
                        Text("No teaching note returned for this rewrite.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Rewrite a message above to see how ToneLayer translates ND communication into NT-readable speech, and why each change helps.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.brandGreenMist.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.brandVioletDark.opacity(0.20), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Composer

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Composer", systemImage: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !appModel.testText.isEmpty {
                    Text("\(appModel.testText.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Rewrite level", selection: $appModel.rewriteLevel) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appModel.rewriteLevel) { _, newValue in appModel.saveLevel(newValue) }
            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $appModel.testText)
                    .frame(minHeight: 220, maxHeight: 360)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                if appModel.testText.isEmpty {
                    Text("Your ND message here…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 10) {
                Button { pasteFromClipboard() } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { appModel.testText = "" } label: {
                    Label("Clear", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appModel.testText.isEmpty)
            }
            Button(action: rewriteComposer) {
                HStack {
                    if isComposerRewriting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isComposerRewriting ? "Rewriting\u{2026}" : "Rewrite")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    isComposerRewriting || appModel.testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.brandVioletDark.opacity(0.45) : Color.brandVioletDark
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isComposerRewriting || appModel.testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !composerStatus.isEmpty {
                Text(composerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Output", selection: $selectedOutput) {
                ForEach(outputTabs, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                Text(composerResultWindowText)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 360)
            .background(Color.brandVioletMist.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if hasComposerOutput {
                HStack(spacing: 10) {
                    Button { copyComposerResult() } label: {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandVioletDark)
                    Button { replaceDraftWithResult() } label: {
                        Label("Replace Draft", systemImage: "arrow.uturn.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if hasComposerOutput { feedbackCard }
            Button { shareComposerResult() } label: {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandVioletDark)
            .disabled(!hasComposerOutput)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feedbackSubmitted ? "Thanks. Feedback saved locally." : "Did this help?")
                .font(.subheadline.weight(.semibold))
            if !feedbackSubmitted {
                HStack(spacing: 8) {
                    feedbackButton("Not really", systemImage: "hand.thumbsdown", clarity: 2, overwhelm: 7)
                    feedbackButton("Somewhat", systemImage: "minus.circle", clarity: 5, overwhelm: 5)
                    feedbackButton("Helped", systemImage: "hand.thumbsup", clarity: 8, overwhelm: 3)
                }
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func feedbackButton(_ title: String, systemImage: String, clarity: Int, overwhelm: Int) -> some View {
        Button {
            submitFeedback(label: title, clarity: clarity, overwhelm: overwhelm)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var hasComposerOutput: Bool {
        !composerOriginal.isEmpty || !composerGrammar.isEmpty || !composerNT.isEmpty
    }

    private var selectedComposerText: String {
        switch selectedOutput {
        case "Original":     return composerOriginal
        case "Grammar only": return composerGrammar.isEmpty ? composerOriginal : composerGrammar
        default:
            if !composerNT.isEmpty       { return composerNT }
            if !composerGrammar.isEmpty  { return composerGrammar }
            return composerOriginal
        }
    }

    private var composerResultWindowText: String {
        guard hasComposerOutput else { return "Rewrite result will appear here." }
        return selectedComposerText.isEmpty ? "Rewrite result will appear here." : selectedComposerText
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else {
            composerStatus = "Clipboard is empty"; return
        }
        appModel.testText = pasted
        composerStatus = "Pasted \(pasted.count) characters"
        appModel.trackOutcome(event: "paste_from_clipboard", inputLength: pasted.count)
    }

    private func copyComposerResult() {
        UIPasteboard.general.string = selectedComposerText
        composerStatus = "Copied \(selectedOutput)"
        appModel.trackOutcome(event: "copy_result")
    }

    private func replaceDraftWithResult() {
        appModel.testText = selectedComposerText
        appModel.sharedDefaults.set(appModel.testText, forKey: "testBoxFullText")
        appModel.sharedDefaults.synchronize()
        composerStatus = "Draft replaced with \(selectedOutput)"
        appModel.trackOutcome(event: "replace_draft")
    }

    private func shareComposerResult() {
        appModel.activityItems = [selectedComposerText]
        appModel.showingExportSheet = true
        composerStatus = "Choose where to share"
        appModel.trackOutcome(event: "share_result")
    }

    private func rewriteComposer() {
        let input = appModel.testText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isComposerRewriting = true
        composerStatus = "Rewriting \(input.count) characters..."
        composerOriginal = input
        composerGrammar = ""
        composerNT = ""
        composerExplanation = ""
        selectedOutput = "NT version"
        feedbackSubmitted = false
        Task {
            do {
                let result = try await callServer(text: input)
                await MainActor.run {
                    composerGrammar     = result.grammarOnly.isEmpty ? input : result.grammarOnly
                    composerNT          = result.rewrite
                    composerExplanation = result.explanation
                    isComposerRewriting = false
                    composerStatus      = "Ready"
                    saveLog(original: input, rewritten: result.rewrite, explanation: result.explanation, distortions: result.distortions)
                    appModel.trackOutcome(event: "rewrite_completed", inputLength: input.count, outputLength: result.rewrite.count,
                                 distortions: result.distortions, correctionMetrics: CorrectionMetrics(original: input, rewritten: result.rewrite))
                    appModel.loadLog()
                }
            } catch {
                await MainActor.run { isComposerRewriting = false; composerStatus = error.localizedDescription }
            }
        }
    }

    private struct ComposerResult {
        let rewrite: String
        let grammarOnly: String
        let explanation: String
        let distortions: [String]
    }

    private func callServer(text: String) async throws -> ComposerResult {
        var req = URLRequest(url: URL(string: AppConfig.serverURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.appToken, forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text":    text,
            "profile": appModel.activeProfileLabel,
            "level":   appModel.rewriteLevel,
            "mode":    "tonelayer"
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ComposerError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJSON["error"] as? String {
                throw ComposerError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw ComposerError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ComposerError.badResponse }
        let rewrite: String
        if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
            rewrite = paras.joined(separator: "\n\n")
        } else {
            rewrite = parsed["rewrite"] as? String ?? ""
        }
        guard !rewrite.isEmpty else { throw ComposerError.badResponse }
        return ComposerResult(
            rewrite:     rewrite,
            grammarOnly: parsed["grammar_only"] as? String ?? "",
            explanation: parsed["explanation"]  as? String ?? "",
            distortions: parsed["distortions"]  as? [String] ?? []
        )
    }

    private func saveLog(original: String, rewritten: String, explanation: String, distortions: [String]) {
        let entry = RewriteEntry(id: UUID(), timestamp: Date(), profile: appModel.activeProfileLabel, mode: appModel.rewriteLevel,
                                 originalText: original, rewrittenText: rewritten,
                                 explanation: explanation, distortions: distortions, spiraling: !distortions.isEmpty)
        DispatchQueue.global(qos: .background).async { LogStore.shared.append(entry) }
    }

    private func submitFeedback(label: String, clarity: Int, overwhelm: Int) {
        feedbackSubmitted = true
        appModel.trackOutcome(event: "feedback_submitted", feedbackLabel: label, clarity: clarity, overwhelm: overwhelm)
    }
}

#Preview {
    ComposerView().environmentObject(AppModel())
}
