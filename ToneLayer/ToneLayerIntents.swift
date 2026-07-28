// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import AppIntents
import ToneLayerCore

// AppIntent.perform() isn't guaranteed to run on the main actor, but this
// project's default actor isolation setting makes top-level `var`/`func`
// declarations MainActor-isolated unless marked `nonisolated` explicitly —
// UserDefaults access itself is thread-safe, so this is safe off-main.
nonisolated private var toneLayerSharedDefaults: UserDefaults? {
    UserDefaults(suiteName: AppConfig.appGroupID)
}

nonisolated private func currentProfile() -> String {
    toneLayerSharedDefaults?.string(forKey: "selectedProfile") ?? "General ND"
}

nonisolated private func currentLevel() -> String {
    let stored = toneLayerSharedDefaults?.string(forKey: "rewriteLevel") ?? "Medium"
    return ["Light", "Medium", "Strong"].contains(stored) ? stored : "Medium"
}

struct RewriteWithToneLayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Rewrite with ToneLayer"
    static var description = IntentDescription("Rewrites your message to sound clearer to a neurotypical reader.")

    @Parameter(title: "Message")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await RewriteRouter().rewrite(
            text: text,
            profile: currentProfile(),
            level: currentLevel(),
            mode: "tonelayer",
            allowOnDevice: false
        )
        return .result(value: result.rewrite, dialog: "Here's your rewrite.")
    }
}

struct DecodeWithToneLayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Decode with ToneLayer"
    static var description = IntentDescription("Reads a message you received and explains what it actually means.")

    @Parameter(title: "Message")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let redactor = PIIRedactor()
        let (redacted, mapping, _) = redactor.redact(text)
        let parsed = try await RewriteRouter.postJSON(url: AppConfig.decodeURL, body: [
            "text": redacted,
            "contact": "Unknown",
            "sensitivity": "Low"
        ])
        let raw = parsed["translation"] as? String
            ?? parsed["summary"] as? String
            ?? parsed["analysis"] as? String
            ?? ""
        let translation = redactor.rehydrate(raw, mapping: mapping)
        return .result(value: translation, dialog: "Here's what that message means.")
    }
}

enum ToneLevel: String, AppEnum {
    case light  = "Light"
    case medium = "Medium"
    case strong = "Strong"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Rewrite Level"
    static var caseDisplayRepresentations: [ToneLevel: DisplayRepresentation] = [
        .light:  "Light",
        .medium: "Medium",
        .strong: "Strong"
    ]
}

struct SetRewriteLevelIntent: AppIntent {
    static var title: LocalizedStringResource = "Set ToneLayer Rewrite Level"
    static var description = IntentDescription("Sets how strongly ToneLayer rewrites your messages.")

    @Parameter(title: "Level")
    var level: ToneLevel

    func perform() async throws -> some IntentResult & ProvidesDialog {
        toneLayerSharedDefaults?.set(level.rawValue, forKey: "rewriteLevel")
        return .result(dialog: "ToneLayer set to \(level.rawValue) rewrites.")
    }
}

struct OpenTonalInsightIntent: AppIntent {
    static var title: LocalizedStringResource = "Open TonalInsight Check-In"
    static var description = IntentDescription("Opens ToneLayer straight to TonalInsight, your executive-function companion.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        toneLayerSharedDefaults?.set("insight", forKey: "requestedTab")
        return .result()
    }
}

struct ToneLayerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RewriteWithToneLayerIntent(),
            phrases: ["Rewrite with \(.applicationName)"],
            shortTitle: "Rewrite",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: DecodeWithToneLayerIntent(),
            phrases: ["Decode this with \(.applicationName)"],
            shortTitle: "Decode",
            systemImageName: "eye.circle"
        )
        AppShortcut(
            intent: SetRewriteLevelIntent(),
            phrases: ["Set \(.applicationName) rewrite level"],
            shortTitle: "Set Rewrite Level",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: OpenTonalInsightIntent(),
            phrases: [
                "Open \(.applicationName) check in",
                "Open TonalInsight in \(.applicationName)"
            ],
            shortTitle: "Open TonalInsight",
            systemImageName: "waveform"
        )
    }
}
