// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation
import NaturalLanguage
import FoundationModels

/// Decides whether a rewrite runs on-device (Apple Intelligence) or in the
/// cloud (Claude), and handles PII redaction for every cloud call.
///
/// Routing rule: Light-level, single-sentence, non-distressed rewrites in
/// `tonelayer`/`clarity` mode go on-device when the caller allows it (the
/// keyboard extension does; the main app never does — the app is for more
/// deliberate composition and always gets the careful cloud pass). Everything
/// else — Medium/Strong, Narc, Decode, multi-sentence text, or a detected
/// vocal-distress flag — goes to the cloud, PII-redacted first.
public struct RewriteRouter {
    private let redactor = PIIRedactor()

    public init() {}

    public func rewrite(
        text: String,
        profile: String,
        level: String,
        mode: String,
        tone: String = "",
        voiceDistressed: Bool = false,
        allowOnDevice: Bool
    ) async throws -> ClaudeResult {
        if allowOnDevice, shouldUseOnDevice(text: text, level: level, mode: mode, voiceDistressed: voiceDistressed) {
            if let result = try? await onDeviceRewrite(text: text, profile: profile, mode: mode) {
                return result
            }
            // On-device unavailable (hardware/Apple Intelligence off) or the
            // model failed to produce usable output — fall through to cloud.
        }
        return try await cloudRewrite(text: text, profile: profile, level: level, mode: mode, tone: tone)
    }

    // MARK: - Routing decision

    private func shouldUseOnDevice(text: String, level: String, mode: String, voiceDistressed: Bool) -> Bool {
        guard level == "Light" else { return false }
        guard mode == "tonelayer" || mode == "clarity" else { return false }
        guard !voiceDistressed else { return false }
        return sentenceCount(in: text) <= 1
    }

    private func sentenceCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return count < 2
        }
        return count
    }

    // MARK: - On-device (FoundationModels)

    private func onDeviceRewrite(text: String, profile: String, mode: String) async throws -> ClaudeResult? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let instructions = Self.lightInstructions(profile: profile, mode: mode)
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewritten.isEmpty else { return nil }

        return ClaudeResult(
            rewrite: rewritten,
            explanation: "Quick on-device rewrite — a light typo/grammar pass.",
            distortions: [],
            grammarOnly: rewritten,
            source: .onDevice
        )
    }

    /// Mirrors the server's Light-level instruction text (see
    /// `toneLayerLevelInstruction`/`clarityLevelInstruction` in
    /// tonelayer-server/prompts.js) so on-device and cloud agree on what
    /// "Light" means. On-device never sees redacted tokens — nothing leaves
    /// the device on this path, so there's nothing to preserve.
    private static func lightInstructions(profile: String, mode: String) -> String {
        if mode == "clarity" {
            return "You are ToneLayer Clarity. Make minimal changes to the user's message: keep their voice, but define vague timing, add missing context, and make any hidden ask explicit. Fix typos and grammar. Reply with only the rewritten text, nothing else — no preamble, no explanation, no quotation marks."
        }
        return "You are ToneLayer. Make a light ND-to-NT rewrite of the user's message for profile \(profile): fix typos and grammar only, and if the main point is completely buried move it to the first sentence. Keep all content and the user's voice intact. Reply with only the rewritten text, nothing else — no preamble, no explanation, no quotation marks."
    }

    // MARK: - Cloud (Claude)

    private func cloudRewrite(text: String, profile: String, level: String, mode: String, tone: String) async throws -> ClaudeResult {
        let (redactedText, mapping, flaggedKinds) = redactor.redact(text)

        var body: [String: Any] = [
            "text":    redactedText,
            "profile": profile,
            "level":   level,
            "mode":    mode
        ]
        if !tone.isEmpty { body["tone"] = tone }

        let parsed = try await Self.postJSON(url: AppConfig.serverURL, body: body)
        return Self.parseRewriteResponse(parsed, mapping: mapping, redactor: redactor, flaggedKinds: flaggedKinds)
    }

    // MARK: - Shared HTTP/JSON helpers

    public static func postJSON(url: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.appToken, forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NBError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJSON["error"] as? String {
                throw NBError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw NBError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NBError.badResponse
        }
        return parsed
    }

    static func parseRewriteResponse(_ parsed: [String: Any], mapping: [String: String], redactor: PIIRedactor, flaggedKinds: Set<String> = []) -> ClaudeResult {
        let rewrite: String
        if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
            rewrite = paras.joined(separator: "\n\n")
        } else {
            rewrite = parsed["rewrite"] as? String ?? ""
        }
        let explanation = parsed["explanation"] as? String ?? ""
        let grammarOnly = parsed["grammar_only"] as? String ?? ""
        let distortions = parsed["distortions"] as? [String] ?? []

        return ClaudeResult(
            rewrite:     redactor.rehydrate(rewrite, mapping: mapping),
            explanation: redactor.rehydrate(explanation, mapping: mapping),
            distortions: distortions,
            grammarOnly: redactor.rehydrate(grammarOnly, mapping: mapping),
            source: .cloud,
            redactionNotice: PIIRedactor.friendlyNotice(for: flaggedKinds)
        )
    }
}
