// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

/// One turn in a Companion conversation.
public struct CompanionMessage: Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String

    public enum Role: String {
        case user
        case assistant
    }

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// The single continuous Companion — unlike `RefineClient`/`RewriteRouter`,
/// which each make an isolated one-shot request, this sends the *whole*
/// conversation so far on every turn, so Claude keeps context across
/// however many exchanges the user has (refining a rewrite, then pivoting
/// to "actually, help me figure out what to prioritize today," in the same
/// thread). PII redaction runs per-turn on whatever new text the user just
/// sent; earlier turns in the mapping are merged in so a name mentioned
/// three turns ago still rehydrates correctly if Claude repeats it back.
public struct CompanionClient {
    private let redactor = PIIRedactor()

    public init() {}

    public struct Result {
        public let reply: String
        /// Set when PIIRedactor found something in `highSensitivityKinds` —
        /// the UI should surface this so the user knows protection happened.
        public let redactionNotice: String?
    }

    public func send(
        history: [CompanionMessage],
        newUserMessage: String,
        rewriteContext: String,
        profile: String,
        tone: String = ""
    ) async throws -> Result {
        // Redact every piece of text going out in one pass so a single
        // shared token counter is used throughout — the same name
        // mentioned in an earlier turn and again in the new message
        // becomes the same [NAME_1] token both times, not two different
        // ones that would each rehydrate correctly on their own but break
        // the "every occurrence of this name is the same token" property
        // the preservation prompt relies on.
        let allTexts = history.map(\.content) + [newUserMessage, rewriteContext]
        let (redactedTexts, mapping, flaggedKinds) = redactor.redactMultiple(allTexts)

        let redactedHistory: [[String: String]] = zip(history, redactedTexts).map { message, redacted in
            ["role": message.role.rawValue, "content": redacted]
        }
        let redactedNewMessage = redactedTexts[history.count]
        let redactedContext = redactedTexts[history.count + 1]

        var messages = redactedHistory
        messages.append(["role": "user", "content": redactedNewMessage])

        var body: [String: Any] = [
            "messages": messages,
            "rewriteContext": redactedContext,
            "profile": profile
        ]
        if !tone.isEmpty { body["tone"] = tone }

        let parsed = try await RewriteRouter.postJSON(url: AppConfig.companionURL, body: body)
        let reply = parsed["reply"] as? String ?? ""
        return Result(
            reply: redactor.rehydrate(reply, mapping: mapping),
            redactionNotice: PIIRedactor.friendlyNotice(for: flaggedKinds)
        )
    }
}
