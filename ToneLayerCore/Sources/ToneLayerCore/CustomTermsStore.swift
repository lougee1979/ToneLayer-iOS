// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

/// User-defined terms (trade secrets, business-confidential names, project
/// codenames — anything PII pattern-matching can't detect because it isn't
/// PII) that `PIIRedactor` also redacts on top of its built-in categories.
/// Stored in the shared app group so both the main app and the keyboard
/// extension see the same list. Nothing here ever leaves the device — this
/// only controls what gets stripped out *before* anything does.
public enum CustomTermsStore {
    private static let key = "customRedactionTerms.v1"

    public static var terms: [String] {
        get {
            UserDefaults(suiteName: AppConfig.appGroupID)?.stringArray(forKey: key) ?? []
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            UserDefaults(suiteName: AppConfig.appGroupID)?.set(cleaned, forKey: key)
        }
    }

    /// Whether the user has gone through the initial setup screen at least
    /// once — lets the app show it once on first launch without re-showing
    /// it every time, even if they left the list empty on purpose.
    private static let setupSeenKey = "customRedactionTermsSetupSeen.v1"

    public static var hasSeenSetup: Bool {
        get { UserDefaults(suiteName: AppConfig.appGroupID)?.bool(forKey: setupSeenKey) ?? false }
        set { UserDefaults(suiteName: AppConfig.appGroupID)?.set(newValue, forKey: setupSeenKey) }
    }
}
