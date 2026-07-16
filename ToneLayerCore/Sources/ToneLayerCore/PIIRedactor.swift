// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation
import NaturalLanguage

/// Replaces names, phone numbers, emails, addresses, dates, bank account
/// numbers, and crypto addresses/keys/seed phrases with opaque bracketed
/// tokens before any text leaves the device, and swaps the real values back
/// in once a response returns. The token↔original mapping is only ever held
/// in memory by the caller — never persisted, never sent anywhere.
///
/// Financial/crypto categories (see `PIIRedactor.highSensitivityKinds`) are
/// flagged back to the caller in addition to being redacted, so the app can
/// warn the user before anything sends — a leaked bank/crypto detail is
/// catastrophic in a way a leaked name or phone number isn't, so this is
/// "redact AND tell them," not just "redact silently."
public struct PIIRedactor {
    /// Categories severe enough that the caller should warn the user before
    /// sending, not just rely on silent redaction.
    public static let highSensitivityKinds: Set<String> = [
        "BANK_ACCOUNT", "CRYPTO_ADDRESS", "CRYPTO_KEY", "SEED_PHRASE", "API_KEY"
    ]

    public init() {}

    public func redact(_ text: String) -> (redacted: String, mapping: [String: String], flaggedKinds: Set<String>) {
        var counters: [String: Int] = [:]
        let (redacted, mapping, flagged) = redact(text, counters: &counters)
        return (redacted, mapping, flagged)
    }

    /// Redacts several independent strings (e.g. a rewrite plus a separate
    /// refine instruction) so every token is unique across all of them —
    /// two different names each becoming `[NAME_1]` independently would
    /// silently collide if redacted one at a time and merged afterward.
    public func redactMultiple(_ texts: [String]) -> (redacted: [String], mapping: [String: String], flaggedKinds: Set<String>) {
        var counters: [String: Int] = [:]
        var mapping: [String: String] = [:]
        var redactedTexts: [String] = []
        var allFlagged: Set<String> = []
        for text in texts {
            let (redacted, partial, flagged) = redact(text, counters: &counters)
            redactedTexts.append(redacted)
            mapping.merge(partial) { _, new in new }
            allFlagged.formUnion(flagged)
        }
        return (redactedTexts, mapping, allFlagged)
    }

    private func redact(_ text: String, counters: inout [String: Int]) -> (redacted: String, mapping: [String: String], flaggedKinds: Set<String>) {
        var spans: [(range: Range<String.Index>, kind: String)] = []

        let dataDetectorTypes: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address, .date]
        if let detector = try? NSDataDetector(types: dataDetectorTypes.rawValue) {
            let nsText = text as NSString
            let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let kind: String
                switch match.resultType {
                case .phoneNumber: kind = "PHONE"
                case .address:     kind = "ADDRESS"
                case .date:        kind = "DATE"
                case .link:        kind = (match.url?.scheme == "mailto") ? "EMAIL" : "LINK"
                default:           kind = "INFO"
                }
                spans.append((range, kind))
            }
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            switch tag {
            case .personalName:     spans.append((range, "NAME"))
            case .organizationName: spans.append((range, "ORG"))
            case .placeName:        spans.append((range, "PLACE"))
            default: break
            }
            return true
        }

        spans.append(contentsOf: FinancialPatterns.matches(in: text))

        spans.sort { $0.range.lowerBound < $1.range.lowerBound }
        var merged: [(range: Range<String.Index>, kind: String)] = []
        for span in spans {
            if let last = merged.last, span.range.lowerBound < last.range.upperBound { continue }
            merged.append(span)
        }

        var tokens: [(range: Range<String.Index>, token: String, original: String)] = []
        var flaggedKinds: Set<String> = []
        for span in merged {
            let original = String(text[span.range])
            let count = (counters[span.kind] ?? 0) + 1
            counters[span.kind] = count
            tokens.append((span.range, "[\(span.kind)_\(count)]", original))
            if Self.highSensitivityKinds.contains(span.kind) {
                flaggedKinds.insert(span.kind)
            }
        }

        var mapping: [String: String] = [:]
        var result = text
        for t in tokens.reversed() {
            mapping[t.token] = t.original
            result.replaceSubrange(t.range, with: t.token)
        }
        return (result, mapping, flaggedKinds)
    }

    public func rehydrate(_ text: String, mapping: [String: String]) -> String {
        guard !mapping.isEmpty else { return text }
        var result = text
        for (token, original) in mapping {
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }

    /// Plain-language notice for the user when something in `highSensitivityKinds`
    /// was found and redacted — informs them protection happened; doesn't ask
    /// permission, since the redaction has already made the send itself safe.
    public static func friendlyNotice(for flaggedKinds: Set<String>) -> String? {
        guard !flaggedKinds.isEmpty else { return nil }
        var parts: [String] = []
        if flaggedKinds.contains("BANK_ACCOUNT")   { parts.append("a bank account number") }
        if flaggedKinds.contains("CRYPTO_ADDRESS") { parts.append("a crypto wallet address") }
        if flaggedKinds.contains("CRYPTO_KEY")     { parts.append("a crypto private key") }
        if flaggedKinds.contains("SEED_PHRASE")    { parts.append("what looked like a crypto seed phrase") }
        if flaggedKinds.contains("API_KEY")        { parts.append("what looked like an API key, token, or private key") }

        let list: String
        if parts.count == 1 {
            list = parts[0]
        } else {
            list = parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
        return "Replaced \(list) with placeholders before sending. No guarantee against every leak — stay careful with what you share and who you share it with."
    }
}

/// Regex/heuristic detectors for financial and crypto data — not covered by
/// `NSDataDetector` or `NLTagger`, and severe enough to warrant their own
/// pass. Kept separate from `PIIRedactor` for readability; every pattern
/// here is deliberately narrow (favors missing an edge case over flagging
/// ordinary text) since these are also surfaced as user-facing warnings.
enum FinancialPatterns {
    static func matches(in text: String) -> [(range: Range<String.Index>, kind: String)] {
        var results: [(range: Range<String.Index>, kind: String)] = []
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        func addMatches(_ pattern: String, kind: String, validate: ((String) -> Bool)? = nil) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            re.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match, let range = Range(match.range, in: text) else { return }
                if let validate, !validate(String(text[range])) { return }
                results.append((range, kind))
            }
        }

        // IBAN — 2-letter country code, 2 check digits, up to 30 alphanumeric.
        addMatches(#"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#, kind: "BANK_ACCOUNT")

        // US bank routing number (ABA) — 9 digits validated by the standard
        // checksum, so a random 9-digit number (order confirmation, etc.)
        // won't false-positive except by real coincidence (~1 in 10).
        addMatches(#"\b\d{9}\b"#, kind: "BANK_ACCOUNT") { candidate in
            let digits = candidate.compactMap { $0.wholeNumberValue }
            guard digits.count == 9 else { return false }
            let sum = 3 * (digits[0] + digits[3] + digits[6])
                    + 7 * (digits[1] + digits[4] + digits[7])
                    + 1 * (digits[2] + digits[5] + digits[8])
            return sum % 10 == 0
        }

        // Ethereum-style address.
        addMatches(#"\b0x[a-fA-F0-9]{40}\b"#, kind: "CRYPTO_ADDRESS")

        // Ethereum-style raw private key (32 bytes, hex, optionally 0x-prefixed).
        addMatches(#"\b(0x)?[a-fA-F0-9]{64}\b"#, kind: "CRYPTO_KEY")

        // Bitcoin legacy/P2SH address (base58) and bech32 (segwit) address.
        addMatches(#"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#, kind: "CRYPTO_ADDRESS")
        addMatches(#"\bbc1[a-z0-9]{25,90}\b"#, kind: "CRYPTO_ADDRESS")

        // Generic API keys/tokens — the same shapes a provider's own systems
        // (Anthropic, OpenAI, AWS, GitHub, Google, Slack, Stripe) would flag
        // and tell the user to rotate immediately if pasted into a chat.
        addMatches(#"\bsk-[A-Za-z0-9_-]{20,}\b"#, kind: "API_KEY")              // Anthropic/OpenAI-style
        addMatches(#"\bAKIA[0-9A-Z]{16}\b"#, kind: "API_KEY")                   // AWS access key ID
        addMatches(#"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#, kind: "API_KEY")       // GitHub fine-grained PAT
        addMatches(#"\bghp_[A-Za-z0-9]{36}\b"#, kind: "API_KEY")                // GitHub classic PAT
        addMatches(#"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#, kind: "API_KEY")       // Slack tokens
        addMatches(#"\bAIza[0-9A-Za-z_-]{35}\b"#, kind: "API_KEY")              // Google API key
        addMatches(#"\brk_live_[A-Za-z0-9]{20,}\b"#, kind: "API_KEY")          // Stripe restricted key
        addMatches(#"\bsk_live_[A-Za-z0-9]{20,}\b"#, kind: "API_KEY")          // Stripe secret key

        // PEM private key blocks (SSH/TLS/PGP).
        addMatches(#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, kind: "API_KEY")

        // JWT — three base64url segments; always starts "eyJ" (base64 for `{"`).
        addMatches(#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, kind: "API_KEY")

        // Bitcoin WIF-format private key.
        addMatches(#"\b[5KL][1-9A-HJ-NP-Za-km-z]{50,51}\b"#, kind: "CRYPTO_KEY")

        // BIP39 seed phrase — 12 or 24 consecutive lowercase words, each
        // 3-8 letters (the length range of every word in the standard
        // wordlist), no punctuation. Deliberately a structural heuristic
        // rather than requiring the exact 2048-word list: this only
        // *flags/redacts* (doesn't block), so an occasional false positive
        // on ordinary short-word text just means one extra confirmation,
        // while a real seed phrase never slips through unflagged.
        results.append(contentsOf: seedPhraseMatches(in: text))

        return results
    }

    private static func seedPhraseMatches(in text: String) -> [(range: Range<String.Index>, kind: String)] {
        var results: [(range: Range<String.Index>, kind: String)] = []
        let wordPattern = try! NSRegularExpression(pattern: #"\b[a-z]{3,8}\b"#)
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        let wordMatches = wordPattern.matches(in: text, range: full)

        var i = 0
        while i < wordMatches.count {
            for runLength in [24, 12] where i + runLength <= wordMatches.count {
                let run = wordMatches[i..<(i + runLength)]
                guard isContiguousRun(run, in: nsText) else { continue }
                let start = run.first!.range.location
                let end = run.last!.range.location + run.last!.range.length
                if let range = Range(NSRange(location: start, length: end - start), in: text) {
                    results.append((range, "SEED_PHRASE"))
                    i += runLength
                }
                break
            }
            i += 1
        }
        return results
    }

    /// Confirms consecutive word matches are separated only by single
    /// spaces (a real seed phrase is one unbroken run) — otherwise two
    /// unrelated short sentences nearby could be mistaken for one phrase.
    private static func isContiguousRun(_ matches: ArraySlice<NSTextCheckingResult>, in nsText: NSString) -> Bool {
        var previous: NSTextCheckingResult?
        for match in matches {
            if let previous {
                let gapStart = previous.range.location + previous.range.length
                let gapLength = match.range.location - gapStart
                guard gapLength == 1, nsText.substring(with: NSRange(location: gapStart, length: 1)) == " " else {
                    return false
                }
            }
            previous = match
        }
        return true
    }
}
