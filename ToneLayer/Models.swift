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

// RewriteEntry / LogStore now live in ToneLayerCore (shared with the
// keyboard extension) — see ToneLayerCore/Sources/ToneLayerCore/RewriteModels.swift.

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

struct PlanStep: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var isDone: Bool = false
}

struct PlanEntry: Codable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var steps: [PlanStep]

    /// The first not-yet-done step — the one thing to focus on right now,
    /// surfaced ahead of the full list so the plan never requires
    /// re-deciding what's next from scratch.
    var nextStep: PlanStep? { steps.first { !$0.isDone } }
}

/// Persists the user's plans (goal broken into ordered, literal steps) so
/// they can be closed and reopened later instead of existing only for the
/// current session — the executive-function point of this feature is that
/// the plan itself remembers, not the user.
final class PlanStore {
    static let shared = PlanStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "plans.json"
    private var storeURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(fileName)
    }
    func loadAll() -> [PlanEntry] {
        guard let url = storeURL, let data = try? Data(contentsOf: url),
              let plans = try? JSONDecoder().decode([PlanEntry].self, from: data) else { return [] }
        return plans.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ plan: PlanEntry) {
        var plans = loadAll()
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else {
            plans.append(plan)
        }
        write(plans)
    }
    func delete(id: UUID) {
        write(loadAll().filter { $0.id != id })
    }
    private func write(_ plans: [PlanEntry]) {
        guard let url = storeURL, let data = try? JSONEncoder().encode(plans) else { return }
        try? data.write(to: url, options: .atomic)
    }
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
