// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

/// The "not quite right? tell it what to fix" pushback control that stands
/// alongside every rewrite result, on-device or cloud. A correction always
/// goes to the AI — it's never handled locally by pattern-matching — and
/// always routes to the cloud, since short targeted instructions don't
/// benefit from the on-device/cloud split the initial rewrite gets.
public struct RefineClient {
    private let redactor = PIIRedactor()

    public init() {}

    public func refine(
        previousRewrite: String,
        instruction: String,
        profile: String,
        level: String,
        mode: String,
        tone: String = ""
    ) async throws -> ClaudeResult {
        let (redactedTexts, mapping, flaggedKinds) = redactor.redactMultiple([previousRewrite, instruction])
        var body: [String: Any] = [
            "previousRewrite": redactedTexts[0],
            "instruction":     redactedTexts[1],
            "profile":         profile,
            "level":           level,
            "mode":            mode
        ]
        if !tone.isEmpty { body["tone"] = tone }

        let parsed = try await RewriteRouter.postJSON(url: AppConfig.refineURL, body: body)
        return RewriteRouter.parseRewriteResponse(parsed, mapping: mapping, redactor: redactor, flaggedKinds: flaggedKinds)
    }
}
