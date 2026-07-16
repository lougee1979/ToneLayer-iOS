// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

/// Where a rewrite was produced — lets the UI show a short "precise
/// rewrite via Claude" vs "quick on-device pass" note without having to
/// guess by inspecting the explanation text.
public enum RewriteSource {
    case onDevice
    case cloud
}

/// The shape both `/rewrite` and `/refine` return, and what an on-device
/// rewrite is wrapped into so the UI never has to branch on where a
/// rewrite came from beyond checking `source`.
public struct ClaudeResult {
    public let rewrite: String
    public let explanation: String
    public let distortions: [String]
    public let grammarOnly: String
    public let source: RewriteSource
    /// Set when PIIRedactor found something in `highSensitivityKinds` (a bank
    /// account, crypto address/key, or seed phrase) — the UI should surface
    /// this so the user knows protection happened, not just silently rely on it.
    public let redactionNotice: String?
    public var isSpiraling: Bool { !distortions.isEmpty }

    public init(rewrite: String, explanation: String, distortions: [String], grammarOnly: String, source: RewriteSource, redactionNotice: String? = nil) {
        self.rewrite = rewrite
        self.explanation = explanation
        self.distortions = distortions
        self.grammarOnly = grammarOnly
        self.source = source
        self.redactionNotice = redactionNotice
    }
}

public enum NBError: LocalizedError {
    case apiFailed(Int)
    case apiMessage(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .apiFailed(let code): return "Server error (HTTP \(code))"
        case .apiMessage(let s):   return s
        case .badResponse:         return "Unexpected server response"
        }
    }
}

public struct RewriteEntry: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let profile: String
    public let mode: String
    public let originalText: String
    public let rewrittenText: String
    public let explanation: String
    public let distortions: [String]
    public let spiraling: Bool

    public init(id: UUID, timestamp: Date, profile: String, mode: String, originalText: String, rewrittenText: String, explanation: String, distortions: [String], spiraling: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.profile = profile
        self.mode = mode
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.explanation = explanation
        self.distortions = distortions
        self.spiraling = spiraling
    }
}

/// Local-only rewrite history — written to the app-group container so both
/// the app and the keyboard extension see the same log, never uploaded.
/// `@unchecked Sendable`: every operation is a fresh, synchronous file
/// read/write with no cached or shared mutable state to race on.
public final class LogStore: @unchecked Sendable {
    public static let shared = LogStore()

    private let fileName = "rewrite_log.json"
    private var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appendingPathComponent(fileName)
    }

    public func load() -> [RewriteEntry] {
        guard let url = logURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RewriteEntry].self, from: data) else { return [] }
        return entries
    }

    public func append(_ entry: RewriteEntry) {
        var entries = load(); entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func topPatterns(limit: Int = 40) -> [(pattern: String, count: Int)] {
        let recent = Array(load().suffix(limit))
        let all = recent.flatMap { $0.distortions }.filter { !$0.isEmpty }
        return Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
            .filter { $0.value >= 2 }.sorted { $0.value > $1.value }
            .prefix(3).map { (pattern: $0.key, count: $0.value) }
    }
}
