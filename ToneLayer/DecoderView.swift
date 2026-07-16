// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import UIKit
import ToneLayerCore

struct DecoderView: View {

    @State private var decodeContactName   = ""
    @State private var decodeText          = ""
    @State private var decodeSensitivity   = "Low"
    @State private var isDecoding          = false
    @State private var decodeTranslation   = ""
    @State private var decodePatterns: [String] = []
    @State private var decodeCommStyle     = ""
    @State private var decodeBaseline      = ""
    @State private var decodeTentative     = false
    @State private var decodeStatus        = ""
    @State private var decodeRedactionNotice: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                decoderCard
            }
            .padding()
        }
        .appBackground()
    }

    private var decoderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Decoder", systemImage: "eye.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
            Text("Paste a message you received. ToneLayer reads it \u{2014} what it actually means, and any patterns worth knowing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Contact name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Who sent this?", text: $decodeContactName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $decodeText)
                    .frame(minHeight: 120, maxHeight: 260)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
                if decodeText.isEmpty {
                    Text("Paste message here\u{2026}")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let clip = UIPasteboard.general.string, !clip.isEmpty { decodeText = clip }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { decodeText = ""; decodeTranslation = ""; decodePatterns = []; decodeCommStyle = ""; decodeBaseline = "" } label: {
                    Label("Clear", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(decodeText.isEmpty)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitivity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Sensitivity", selection: $decodeSensitivity) {
                    ForEach(["Low", "Medium", "High"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(decodeSensitivityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: startDecode) {
                HStack {
                    if isDecoding { ProgressView().tint(.white) }
                    else { Image(systemName: "eye") }
                    Text(isDecoding ? "Decoding\u{2026}" : "Decode")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isDecoding ? Color(red: 0.10, green: 0.36, blue: 0.86).opacity(0.45) : Color(red: 0.10, green: 0.36, blue: 0.86))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isDecoding)

            if !decodeStatus.isEmpty {
                Text(decodeStatus)
                    .font(.subheadline)
                    .foregroundStyle(decodeStatus.contains("…") ? Color.secondary : Color.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(decodeStatus.contains("…") ? Color.clear : Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let notice = decodeRedactionNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Color.brandVioletDark)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandVioletMist)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !decodeTranslation.isEmpty {
                decodeResultsView
            }
        }
        .padding(20)
        .glassCard(tint: Color(red: 0.10, green: 0.36, blue: 0.86))
    }

    private var decodeSensitivityDescription: String {
        switch decodeSensitivity {
        case "Low":    return "Only surfaces clear, strong signals. Recommended."
        case "Medium": return "Flags moderate patterns and clear signals."
        case "High":   return "Flags subtle patterns. May over-flag."
        default:       return ""
        }
    }

    private var decodeResultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("What it\u{2019}s saying", systemImage: "message.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                Text(decodeTranslation)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !decodePatterns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Patterns flagged", systemImage: "flag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.12, blue: 0.12))
                    ForEach(decodePatterns, id: \.self) { pattern in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.15))
                                .padding(.top, 2)
                            Text(pattern)
                                .font(.subheadline)
                                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.18))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !decodeCommStyle.isEmpty && !decodeCommStyle.lowercased().hasPrefix("neutral") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Communication style", systemImage: "brain.head.profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.44, green: 0.18, blue: 0.62))
                    Text(decodeCommStyle)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !decodeBaseline.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                        .padding(.top, 2)
                    Text(decodeBaseline)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if decodeTentative {
                Text("Baseline still building \u{2014} read is tentative.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(red: 0.89, green: 0.93, blue: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(red: 0.10, green: 0.36, blue: 0.86).opacity(0.25), lineWidth: 1))
    }

    private func startDecode() {
        if decodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let clip = UIPasteboard.general.string, !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                decodeText = clip
            } else {
                decodeStatus = "Nothing to decode — copy a message first."
                return
            }
        }
        let text = decodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDecoding = true
        decodeStatus = "Decoding\u{2026}"
        decodeTranslation = ""; decodePatterns = []; decodeCommStyle = ""; decodeBaseline = ""
        Task {
            do {
                let result = try await callDecode(text: text)
                await MainActor.run {
                    isDecoding = false
                    decodeStatus = ""
                    decodeRedactionNotice = result.redactionNotice
                    decodeTranslation = result.translation
                    decodePatterns    = result.patterns
                    decodeCommStyle   = result.commStyle
                    decodeBaseline    = result.baseline
                    decodeTentative   = result.tentative
                    let contact = decodeContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    DecodeStore.shared.append(DecodeEntry(
                        id: UUID(), timestamp: Date(),
                        contact: contact.isEmpty ? "Unknown" : contact,
                        text: text, sensitivity: decodeSensitivity,
                        translation: result.translation, patterns: result.patterns, baseline: result.baseline
                    ))
                }
            } catch {
                await MainActor.run {
                    isDecoding = false
                    decodeStatus = error.localizedDescription
                }
            }
        }
    }

    private struct DecodeResult {
        let translation: String
        let patterns: [String]
        let commStyle: String
        let baseline: String
        let tentative: Bool
        let redactionNotice: String?
    }

    /// A computed summary — message count, average length, and which
    /// patterns have shown up before — never the raw prior message text
    /// itself. This is what tonelayer-server's `/decode` prompt actually
    /// reads (`baseline.messageCount`/`avgLength`/`observedPatterns`); it
    /// previously received an unused raw `history` field of past message
    /// text instead, which the server ignored but the client still sent
    /// over the network for no benefit.
    private func computeBaseline(history: [DecodeEntry]) -> [String: Any]? {
        guard !history.isEmpty else { return nil }
        let avgLength = history.map { $0.text.count }.reduce(0, +) / history.count
        let observedPatterns = Array(Set(history.flatMap { $0.patterns })).prefix(5)
        return [
            "messageCount": history.count,
            "avgLength": avgLength,
            "observedPatterns": Array(observedPatterns)
        ]
    }

    private func callDecode(text: String) async throws -> DecodeResult {
        let contact = decodeContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = DecodeStore.shared.messages(for: contact)

        let redactor = PIIRedactor()
        let (redactedTexts, mapping, flaggedKinds) = redactor.redactMultiple([text, contact.isEmpty ? "Unknown" : contact])

        var body: [String: Any] = [
            "text":        redactedTexts[0],
            "contact":     redactedTexts[1],
            "sensitivity": decodeSensitivity
        ]
        if let baseline = computeBaseline(history: history) { body["baseline"] = baseline }

        let parsed = try await RewriteRouter.postJSON(url: AppConfig.decodeURL, body: body)

        let translation = redactor.rehydrate(
            parsed["translation"] as? String ?? parsed["summary"] as? String ?? parsed["analysis"] as? String ?? "",
            mapping: mapping
        )
        guard !translation.isEmpty else { throw ComposerError.badResponse }
        let patterns = (parsed["flags"] as? [String] ?? parsed["patterns"] as? [String] ?? [])
            .map { redactor.rehydrate($0, mapping: mapping) }
        let commStyle = parsed["communication_style"] as? String ?? ""
        let baseline = parsed["baseline_note"] as? String ?? parsed["baseline"] as? String ?? parsed["note"] as? String ?? ""
        let isDefinitive = parsed["is_definitive"] as? Bool ?? true
        let tentative = !isDefinitive || baseline.lowercased().contains("building") || baseline.lowercased().contains("tentative")
        return DecodeResult(translation: translation, patterns: patterns, commStyle: commStyle, baseline: baseline, tentative: tentative, redactionNotice: PIIRedactor.friendlyNotice(for: flaggedKinds))
    }
}

#Preview { DecoderView() }
