// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

/// Single source of truth for server endpoints and shared identifiers —
/// previously duplicated separately in the app (`SharedUI.swift`) and the
/// keyboard extension (`KeyboardViewController.swift`).
public enum AppConfig {
    public static let serverURL    = "https://tonelayer-server-production.up.railway.app/rewrite"
    public static let refineURL    = "https://tonelayer-server-production.up.railway.app/refine"
    public static let companionURL = "https://tonelayer-server-production.up.railway.app/companion"
    public static let narcURL      = "https://tonelayer-server-production.up.railway.app/narc"
    public static let decodeURL    = "https://tonelayer-server-production.up.railway.app/decode"
    public static let analyticsURL = "https://tonelayer-server-production.up.railway.app/analytics"
    public static let appToken     = Secrets.appToken
    public static let appGroupID   = "group.com.alden.tonelayer"
}
