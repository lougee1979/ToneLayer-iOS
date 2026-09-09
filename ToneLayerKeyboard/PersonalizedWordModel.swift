// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation
import ToneLayerCore

/// Builds a personalized next-word model from the user's own past
/// rewrites — already stored on-device in the shared app-group container
/// via `LogStore`, which the keyboard extension already reads for other
/// settings — so predictive text reflects how this specific person
/// actually writes instead of a small hand-written generic table.
///
/// Deliberately not backed by an on-device LLM (e.g. Apple's Foundation
/// Models): custom keyboard extensions are capped at 48MB of RAM, and
/// this extension already runs live audio (Hume tone WebSocket, speech
/// recognition) in that same budget — a real model in-process risks
/// exactly the kind of memory-pressure crash that limit exists to
/// prevent. This is a plain word-frequency table instead: no network,
/// negligible memory, built once per keyboard session.
struct PersonalizedWordModel {
    private var table: [String: [String: Int]] = [:]

    init() {
        for entry in LogStore.shared.load() {
            ingest(entry.rewrittenText)
        }
    }

    private mutating func ingest(_ text: String) {
        let words = text.split { !$0.isLetter && $0 != "'" }.map { $0.lowercased() }
        guard words.count > 1 else { return }
        for i in 0..<(words.count - 1) {
            table[words[i], default: [:]][words[i + 1], default: 0] += 1
        }
    }

    /// Top follow-up words for `lastWord`, most frequent first in the
    /// user's own history — empty if this word has never been seen.
    func followers(of lastWord: String, limit: Int = 3) -> [String] {
        guard let counts = table[lastWord.lowercased()], !counts.isEmpty else { return [] }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }
}
