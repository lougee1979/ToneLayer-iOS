// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation

struct CorrectionMetrics: Codable {
    let changeScore: Int
    init(original: String, rewritten: String) {
        let o = original.split { $0.isWhitespace }.count
        let r = rewritten.split { $0.isWhitespace }.count
        changeScore = o == 0 ? 0 : min(100, abs(o - r) * 100 / o)
    }
}

struct OutcomeEvent: Codable {
    let id: UUID; let timestamp: Date; let event: String
    let inputLength: Int; let outputLength: Int; let distortions: [String]
    let correctionMetrics: CorrectionMetrics?
    let feedbackLabel: String?; let clarity: Int?; let overwhelm: Int?
}

final class OutcomeStore {
    static let shared = OutcomeStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "outcome_events.json"
    private var storeURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(fileName)
    }
    func load() -> [OutcomeEvent] {
        guard let url = storeURL, let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([OutcomeEvent].self, from: data) else { return [] }
        return events
    }
    func append(_ event: OutcomeEvent) {
        var events = load(); events.append(event)
        if events.count > 1000 { events = Array(events.suffix(1000)) }
        guard let url = storeURL, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct RewriteEntry: Codable, Identifiable {
    let id: UUID; let timestamp: Date; let profile: String; let mode: String
    let originalText: String; let rewrittenText: String
    let explanation: String; let distortions: [String]; let spiraling: Bool
}

final class LogStore {
    static let shared = LogStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "rewrite_log.json"
    private var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(fileName)
    }
    func load() -> [RewriteEntry] {
        guard let url = logURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RewriteEntry].self, from: data) else { return [] }
        return entries
    }
    func append(_ entry: RewriteEntry) {
        var entries = load(); entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct DecodeEntry: Codable {
    let id: UUID
    let timestamp: Date
    let contact: String
    let text: String
    let sensitivity: String
    let translation: String
    let patterns: [String]
    let baseline: String
}

final class DecodeStore {
    static let shared = DecodeStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "decode_log.json"
    private var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(fileName)
    }
    func load() -> [DecodeEntry] {
        guard let url = logURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DecodeEntry].self, from: data) else { return [] }
        return entries
    }
    func messages(for contact: String) -> [DecodeEntry] {
        guard !contact.isEmpty else { return [] }
        return load().filter { $0.contact.lowercased() == contact.lowercased() }
    }
    func append(_ entry: DecodeEntry) {
        var entries = load(); entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
