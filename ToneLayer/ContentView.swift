//
//  ContentView.swift
//  ToneLayer
//
//  Created by Alden-Edwin Lougee on 5/3/26.
//

import SwiftUI
import UIKit

extension Color {
    static let brandVioletDark = Color(red: 0.369, green: 0.122, blue: 0.784)
    static let brandViolet     = Color(red: 0.220, green: 0.502, blue: 0.973)
    static let brandGreen      = Color(red: 0.608, green: 0.247, blue: 0.910)
    static let brandWhite      = Color(red: 0.976, green: 0.969, blue: 1.000)
    static let brandGreenMist  = Color(red: 0.882, green: 0.914, blue: 0.996)
    static let brandVioletMist = Color(red: 0.929, green: 0.878, blue: 1.000)
}

struct GlassCard: ViewModifier {
    var tint: Color = .brandGreen
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.brandWhite.opacity(0.42), tint.opacity(0.16), Color.brandViolet.opacity(0.14), Color.brandVioletDark.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.brandWhite.opacity(0.78), tint.opacity(0.42), Color.brandViolet.opacity(0.34), Color.brandVioletDark.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard(tint: Color = .brandGreen, cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius))
    }
}

struct ContentView: View {

    @State private var profileADHD   = false
    @State private var profileAutism  = true
    @State private var profileAUDHD   = false
    @State private var profilePTSD    = false
    @State private var profileCPTSD   = false
    @State private var rewriteLevel        = "Medium"
    @State private var testText            = ""
    @State private var spiralPauseEnabled  = true
    @State private var spiralSensitivity   = "Medium"
    @State private var showExplanation     = true
    @State private var outcomesOptIn       = false
    @State private var logEntries: [RewriteEntry] = []
    @State private var outcomeEvents: [OutcomeEvent] = []
    @State private var isComposerRewriting = false
    @State private var composerStatus      = ""
    @State private var composerOriginal    = ""
    @State private var composerGrammar     = ""
    @State private var composerNT          = ""
    @State private var composerExplanation = ""
    @State private var selectedOutput      = "NT version"
    @State private var feedbackSubmitted   = false
    @State private var activityItems: [Any] = []
    @State private var showingExportSheet  = false

    // Decoder
    @State private var decodeContactName   = ""
    @State private var decodeText          = ""
    @State private var decodeSensitivity   = "Low"
    @State private var isDecoding          = false
    @State private var decodeTranslation   = ""
    @State private var decodePatterns: [String] = []
    @State private var decodeCommStyle     = ""
    @State private var decodeBaseline      = ""
    @State private var decodeTentative     = false
    @State private var decodeStatus        = ""

    private let sensitivities = ["Low", "Medium", "High"]
    private let outputTabs = ["Original", "Grammar only", "NT version"]

    private let serverURL = "https://tonelayer-server-production.up.railway.app/rewrite"
    private let decodeURL = "https://tonelayer-server-production.up.railway.app/decode"
    private let appToken  = "d731136d97cdd46453e7581465537e0d9aee811512b885c2"

    private let dailyTips: [(title: String, body: String)] = [
        (
            "RSD can make silence feel personal",
            "Rejection sensitivity is common for many people with ADHD. A delayed reply, a blocked call, or a short message can feel like proof that something is wrong, even when the other person is only busy or overwhelmed."
        ),
        (
            "Direct does not mean rude",
            "Many neurodivergent people communicate best with clear, specific language. A direct request can reduce guessing, anxiety, and the pressure to decode hidden meaning."
        ),
        (
            "Too many options can freeze action",
            "When everything feels equally urgent, the brain may stall instead of choosing. Naming one next step can be more helpful than giving a full list of possible solutions."
        ),
        (
            "Tone can get lost in text",
            "Short messages can be read as anger or rejection when the nervous system is already activated. Adding one warm sentence can change how safe the message feels."
        ),
        (
            "Body doubling is practical support",
            "Some people start tasks more easily when another person is present or checking in. It is not dependence; it can be a way to borrow structure long enough to begin."
        ),
        (
            "Clarity lowers the social load",
            "A message that says what happened, what is needed, and when a reply is expected gives the other person fewer hidden steps to interpret."
        ),
        (
            "Overexplaining can be a safety behavior",
            "A long message may be an attempt to prevent misunderstanding, criticism, or rejection. The goal is not to remove the person's voice, but to organize it so the need is clear."
        )
    ]

    private let appGroupID              = "group.com.alden.tonelayer"
    private let selectedProfileKey      = "selectedProfile"
    private let rewriteLevelKey         = "rewriteLevel"
    private let spiralPauseEnabledKey   = "spiralPauseEnabled"
    private let spiralSensitivityKey    = "spiralSensitivity"
    private let showExplanationKey      = "showExplanation.v2"
    private let outcomesOptInKey        = "outcomesOptIn"

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private var activeProfileLabel: String {
        var p: [String] = []
        if profileAUDHD {
            p.append("AUDHD")
        } else {
            if profileADHD   { p.append("ADHD") }
            if profileAutism { p.append("Autism") }
        }
        if profilePTSD   { p.append("PTSD") }
        if profileCPTSD  { p.append("CPTSD") }
        return p.isEmpty ? "General ND" : p.joined(separator: " + ")
    }

    private func syncProfileSettings() {
        UserDefaults.standard.set(profileADHD,   forKey: "ndprofile.adhd")
        UserDefaults.standard.set(profileAutism, forKey: "ndprofile.autism")
        UserDefaults.standard.set(profileAUDHD,  forKey: "ndprofile.audhd")
        UserDefaults.standard.set(profilePTSD,   forKey: "ndprofile.ptsd")
        UserDefaults.standard.set(profileCPTSD,  forKey: "ndprofile.cptsd")
        sharedDefaults.set(activeProfileLabel,   forKey: selectedProfileKey)
        sharedDefaults.set(profileADHD,          forKey: "ndprofile.adhd")
        sharedDefaults.set(profileAutism,        forKey: "ndprofile.autism")
        sharedDefaults.set(profileAUDHD,         forKey: "ndprofile.audhd")
        sharedDefaults.set(profilePTSD,          forKey: "ndprofile.ptsd")
        sharedDefaults.set(profileCPTSD,         forKey: "ndprofile.cptsd")
        sharedDefaults.synchronize()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                dailyTipCard
                composerCard
                decoderCard
                teachingCard
                settingsSection
                logCard
            }
            .padding()
        }
        .background(Color(red: 0.945, green: 0.937, blue: 0.984))
        .preferredColorScheme(.light)
        .onAppear {
            loadSettings()
            loadLog()
            loadOutcomeEvents()
        }
        .sheet(isPresented: $showingExportSheet) {
            ActivityView(activityItems: activityItems)
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image("ToneLayerLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("ToneLayer")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.brandGreen)
            Text("Write it out your way. ToneLayer translates it into NT-readable communication.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(tint: .brandGreen)
    }

    private var dailyTipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FYI of the day", systemImage: "sparkle.magnifyingglass")
                .font(.headline)
                .foregroundStyle(Color.brandVioletDark)
            Text(todayTip.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(todayTip.body)
                .font(.subheadline)
                .foregroundStyle(Color(red: 0.22, green: 0.26, blue: 0.30))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(tint: .brandViolet, cornerRadius: 18)
    }

    private var todayTip: (title: String, body: String) {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dailyTips[(day - 1) % dailyTips.count]
    }

    private var teachingCard: some View {
        Group {
            if showExplanation {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How this lands", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(Color.brandVioletDark)
                    if hasComposerOutput && !composerExplanation.isEmpty {
                        Text(composerExplanation)
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if hasComposerOutput {
                        Text("No teaching note returned for this rewrite.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Rewrite a message above to see how ToneLayer translates ND communication into NT-readable speech, and why each change helps.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.brandGreenMist.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.brandVioletDark.opacity(0.20), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Decoder

    private var decoderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Decoder", systemImage: "eye.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
            Text("Paste a message you received. ToneLayer reads it \u{2014} what it actually means, and any patterns worth knowing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Contact name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Who sent this?", text: $decodeContactName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $decodeText)
                    .frame(minHeight: 120, maxHeight: 260)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
                if decodeText.isEmpty {
                    Text("Paste message here\u{2026}")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let clip = UIPasteboard.general.string, !clip.isEmpty { decodeText = clip }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { decodeText = ""; decodeTranslation = ""; decodePatterns = []; decodeCommStyle = ""; decodeBaseline = "" } label: {
                    Label("Clear", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(decodeText.isEmpty)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitivity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Sensitivity", selection: $decodeSensitivity) {
                    ForEach(["Low", "Medium", "High"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(decodeSensitivityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: startDecode) {
                HStack {
                    if isDecoding { ProgressView().tint(.white) }
                    else { Image(systemName: "eye") }
                    Text(isDecoding ? "Decoding\u{2026}" : "Decode")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isDecoding ? Color(red: 0.10, green: 0.36, blue: 0.86).opacity(0.45) : Color(red: 0.10, green: 0.36, blue: 0.86))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isDecoding)

            if !decodeStatus.isEmpty {
                Text(decodeStatus)
                    .font(.subheadline)
                    .foregroundStyle(decodeStatus.contains("…") ? Color.secondary : Color.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(decodeStatus.contains("…") ? Color.clear : Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !decodeTranslation.isEmpty {
                decodeResultsView
            }
        }
        .padding(20)
        .glassCard(tint: Color(red: 0.10, green: 0.36, blue: 0.86))
    }

    private var decodeSensitivityDescription: String {
        switch decodeSensitivity {
        case "Low":    return "Only surfaces clear, strong signals. Recommended."
        case "Medium": return "Flags moderate patterns and clear signals."
        case "High":   return "Flags subtle patterns. May over-flag."
        default:       return ""
        }
    }

    private var decodeResultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("What it\u{2019}s saying", systemImage: "message.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                Text(decodeTranslation)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !decodePatterns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Patterns flagged", systemImage: "flag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.12, blue: 0.12))
                    ForEach(decodePatterns, id: \.self) { pattern in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.15))
                                .padding(.top, 2)
                            Text(pattern)
                                .font(.subheadline)
                                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.18))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !decodeCommStyle.isEmpty && !decodeCommStyle.lowercased().hasPrefix("neutral") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Communication style", systemImage: "brain.head.profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.44, green: 0.18, blue: 0.62))
                    Text(decodeCommStyle)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !decodeBaseline.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                        .padding(.top, 2)
                    Text(decodeBaseline)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if decodeTentative {
                Text("Baseline still building \u{2014} read is tentative.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(red: 0.89, green: 0.93, blue: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(red: 0.10, green: 0.36, blue: 0.86).opacity(0.25), lineWidth: 1))
    }

    private func startDecode() {
        if decodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let clip = UIPasteboard.general.string, !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                decodeText = clip
            } else {
                decodeStatus = "Nothing to decode — copy a message first."
                return
            }
        }
        let text = decodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDecoding = true
        decodeStatus = "Decoding\u{2026}"
        decodeTranslation = ""; decodePatterns = []; decodeCommStyle = ""; decodeBaseline = ""
        Task {
            do {
                let result = try await callDecode(text: text)
                await MainActor.run {
                    isDecoding = false
                    decodeStatus = ""
                    decodeTranslation = result.translation
                    decodePatterns    = result.patterns
                    decodeCommStyle   = result.commStyle
                    decodeBaseline    = result.baseline
                    decodeTentative   = result.tentative
                    let contact = decodeContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    DecodeStore.shared.append(DecodeEntry(
                        id: UUID(), timestamp: Date(),
                        contact: contact.isEmpty ? "Unknown" : contact,
                        text: text, sensitivity: decodeSensitivity,
                        translation: result.translation, patterns: result.patterns, baseline: result.baseline
                    ))
                }
            } catch {
                await MainActor.run {
                    isDecoding = false
                    decodeStatus = error.localizedDescription
                }
            }
        }
    }

    private struct DecodeResult {
        let translation: String
        let patterns: [String]
        let commStyle: String
        let baseline: String
        let tentative: Bool
    }

    private func callDecode(text: String) async throws -> DecodeResult {
        let contact = decodeContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = DecodeStore.shared.messages(for: contact)
        var req = URLRequest(url: URL(string: decodeURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken,           forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text":        text,
            "contact":     contact.isEmpty ? "Unknown" : contact,
            "sensitivity": decodeSensitivity,
            "history":     history.suffix(10).map { ["text": $0.text, "patterns": $0.patterns] }
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ComposerError.apiFailed(0) }
        if http.statusCode != 200 {
            if let e = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = e["error"] as? String {
                throw ComposerError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw ComposerError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ComposerError.badResponse }
        let translation = parsed["translation"] as? String
            ?? parsed["summary"]  as? String
            ?? parsed["analysis"] as? String
            ?? ""
        guard !translation.isEmpty else { throw ComposerError.badResponse }
        let patterns = parsed["flags"] as? [String] ?? parsed["patterns"] as? [String] ?? []
        let commStyle = parsed["communication_style"] as? String ?? ""
        let baseline = parsed["baseline_note"] as? String ?? parsed["baseline"] as? String ?? parsed["note"] as? String ?? ""
        let isDefinitive = parsed["is_definitive"] as? Bool ?? true
        let tentative = !isDefinitive || baseline.lowercased().contains("building") || baseline.lowercased().contains("tentative")
        return DecodeResult(translation: translation, patterns: patterns, commStyle: commStyle, baseline: baseline, tentative: tentative)
    }

    // MARK: - Composer

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Composer", systemImage: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !testText.isEmpty {
                    Text("\(testText.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Rewrite level", selection: $rewriteLevel) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: rewriteLevel) { _, newValue in saveLevel(newValue) }
            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $testText)
                    .frame(minHeight: 220, maxHeight: 360)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                if testText.isEmpty {
                    Text("Your ND message here…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 10) {
                Button { pasteFromClipboard() } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { testText = "" } label: {
                    Label("Clear", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(testText.isEmpty)
            }
            Button(action: rewriteComposer) {
                HStack {
                    if isComposerRewriting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isComposerRewriting ? "Rewriting\u{2026}" : "Rewrite")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    isComposerRewriting || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.brandVioletDark.opacity(0.45) : Color.brandVioletDark
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isComposerRewriting || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !composerStatus.isEmpty {
                Text(composerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Output", selection: $selectedOutput) {
                ForEach(outputTabs, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                Text(composerResultWindowText)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 360)
            .background(Color.brandVioletMist.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if hasComposerOutput {
                HStack(spacing: 10) {
                    Button { copyComposerResult() } label: {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandVioletDark)
                    Button { replaceDraftWithResult() } label: {
                        Label("Replace Draft", systemImage: "arrow.uturn.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if hasComposerOutput { feedbackCard }
            Button { shareComposerResult() } label: {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandVioletDark)
            .disabled(!hasComposerOutput)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private var settingsSection: some View {
        DisclosureGroup {
            VStack(spacing: 20) {
                privacyAndOutcomesCard
                outcomesSummaryCard
                profileCard
                levelCard
                spiralPauseCard
                explanationToggleCard
                testCard
                statusCard
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Label("Options", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.down.circle.fill")
                    .foregroundStyle(Color.brandVioletDark)
            }
        }
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feedbackSubmitted ? "Thanks. Feedback saved locally." : "Did this help?")
                .font(.subheadline.weight(.semibold))
            if !feedbackSubmitted {
                HStack(spacing: 8) {
                    feedbackButton("Not really", systemImage: "hand.thumbsdown", clarity: 2, overwhelm: 7)
                    feedbackButton("Somewhat", systemImage: "minus.circle", clarity: 5, overwhelm: 5)
                    feedbackButton("Helped", systemImage: "hand.thumbsup", clarity: 8, overwhelm: 3)
                }
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func feedbackButton(_ title: String, systemImage: String, clarity: Int, overwhelm: Int) -> some View {
        Button {
            submitFeedback(label: title, clarity: clarity, overwhelm: overwhelm)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var privacyAndOutcomesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Personalization & Outcomes", systemImage: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.semibold))
            Text("Optional consent for using ADHD evaluation data and ToneLayer activity patterns to personalize support and measure whether the tools are helping.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use my data to personalize support").font(.subheadline.weight(.semibold))
                    Text("When this is off, ToneLayer should only use local settings needed for the current rewrite.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $outcomesOptIn).labelsHidden()
                    .onChange(of: outcomesOptIn) { _, v in sharedDefaults.set(v, forKey: outcomesOptInKey) }
            }
            Text("Future payer or clinical reports should require this opt-in and should show function-level outcomes, not private draft text.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private var outcomesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Local Outcomes", systemImage: "chart.bar.xaxis").font(.title3.weight(.semibold))
                Spacer()
                Text(outcomesOptIn ? "On" : "Off").font(.caption.weight(.semibold))
                    .foregroundStyle(outcomesOptIn ? .green : .secondary)
            }
            if !outcomesOptIn {
                Text("Turn on Personalization & Outcomes to collect local event summaries.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if outcomeEvents.isEmpty {
                Text("No local outcome events yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                let rewrites = outcomeEvents.filter { $0.event == "rewrite_completed" }.count
                let exports  = outcomeEvents.filter { $0.event.hasPrefix("export_") || $0.event == "copy_result" }.count
                let feedback = outcomeEvents.filter { $0.event == "feedback_submitted" }.count
                let latest   = outcomeEvents.suffix(30)
                let avgInput = latest.isEmpty ? 0 : latest.map(\.inputLength).reduce(0,+) / latest.count
                let scores   = outcomeEvents.compactMap { $0.correctionMetrics?.changeScore }
                let avgCorr  = scores.isEmpty ? 0 : scores.reduce(0,+) / scores.count
                VStack(spacing: 8) {
                    outcomeRow("Tracked events", "\(outcomeEvents.count)")
                    outcomeRow("Rewrites", "\(rewrites)")
                    outcomeRow("Exports / copies", "\(exports)")
                    outcomeRow("Feedback submitted", "\(feedback)")
                    outcomeRow("Avg input length", "\(avgInput) chars")
                    outcomeRow("Avg correction", "\(avgCorr)%")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private func outcomeRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ND Profile", systemImage: "person.crop.circle").font(.title3.weight(.semibold))
            Text("Check all that apply. AUDHD = ADHD + Autism combined.")
                .foregroundStyle(.secondary).font(.subheadline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                profileCheckbox("ADHD",   isOn: $profileADHD)
                profileCheckbox("Autism", isOn: $profileAutism)
                profileCheckbox("AUDHD",  isOn: $profileAUDHD)
                profileCheckbox("PTSD",   isOn: $profilePTSD)
                profileCheckbox("CPTSD",  isOn: $profileCPTSD)
            }
            if activeProfileLabel != "General ND" {
                Label("Active: \(activeProfileLabel)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandVioletDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private func profileCheckbox(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            syncProfileSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? Color.brandVioletDark : Color.secondary)
                    .font(.body)
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(isOn.wrappedValue ? Color.brandVioletMist : Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isOn.wrappedValue ? Color.brandVioletDark.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private let levelDescriptions: [String: String] = [
        "Light":  "Small ND-to-NT adjustments: fixes clarity, grammar, and tone while keeping your wording close.",
        "Medium": "Balanced ND-to-NT rewrite: restructures the message for NT readers while still sounding like you.",
        "Strong": "Full ND-to-NT translation: concise, direct, emotionally neutral, and easy for NT readers to act on.",
    ]

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("NT Level", systemImage: "sparkles").font(.title3.weight(.semibold))
            Text("Choose how strongly ToneLayer should translate ND speech into NT speech.")
                .foregroundStyle(.secondary).font(.subheadline)
            VStack(spacing: 10) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                    Button { saveLevel(l) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l).fontWeight(.semibold)
                                    .foregroundStyle(rewriteLevel == l ? Color(red:0.12,green:0.15,blue:0.18) : Color.primary)
                                if let desc = levelDescriptions[l] {
                                    Text(desc).font(.caption)
                                        .foregroundStyle(rewriteLevel == l ? Color(red:0.30,green:0.34,blue:0.38) : Color.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if rewriteLevel == l {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brandVioletDark)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(rewriteLevel == l ? Color.brandVioletMist : Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandGreen)
    }

    private var spiralPauseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Spiral Pause", systemImage: "heart.circle").font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: $spiralPauseEnabled).labelsHidden()
                    .onChange(of: spiralPauseEnabled) { _, v in sharedDefaults.set(v, forKey: spiralPauseEnabledKey) }
            }
            Text("Before rewriting, ToneLayer checks if your text shows cognitive distortions. If it does, it pauses and offers a calmer draft.")
                .foregroundStyle(.secondary).font(.subheadline)
            if spiralPauseEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity").font(.subheadline.weight(.medium))
                    Picker("Sensitivity", selection: $spiralSensitivity) {
                        ForEach(sensitivities, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: spiralSensitivity) { _, v in sharedDefaults.set(v, forKey: spiralSensitivityKey) }
                    Text(sensitivityDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandGreen)
    }

    private var explanationToggleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Teaching Window", systemImage: "lightbulb").font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: $showExplanation).labelsHidden()
                    .onChange(of: showExplanation) { _, v in sharedDefaults.set(v, forKey: showExplanationKey) }
            }
            Text("Shows teaching explanation below every rewrite. Turn it off here if you only want the rewrite output.")
                .foregroundStyle(.secondary).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandVioletDark)
    }

    private var sensitivityDescription: String {
        switch spiralSensitivity {
        case "Low":  return "Only pauses on strong signals."
        case "High": return "Pauses on any clear distortion. May feel intrusive."
        default:     return "Pauses when two or more distortions are present. Recommended."
        }
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keyboard Test", systemImage: "keyboard").font(.title3.weight(.semibold))
                Spacer()
                if !testText.isEmpty { Button("Clear") { testText = "" }.font(.subheadline) }
            }
            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $testText)
                    .frame(minHeight: 180, maxHeight: 320).padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5))
                if testText.isEmpty {
                    Text("Type or paste your text here\u{2026}")
                        .foregroundStyle(.tertiary).font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
            HStack { Spacer(); Text("\(testText.count) characters").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandVioletDark)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Status", systemImage: "checkmark.seal").font(.title3.weight(.semibold))
            statusRow(title: "Host app",           value: "\u{2713} Running")
            statusRow(title: "Keyboard extension", value: "\u{2713} Installed")
            statusRow(title: "Server",             value: "\u{2713} railway.app")
            statusRow(title: "Active profile",     value: activeProfileLabel)
            statusRow(title: "NT level",            value: rewriteLevel)
            statusRow(title: "App group sharing",  value: "\u{2713} Enabled")
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandGreen)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.semibold) }
    }

    private func loadSettings() {
        profileADHD   = UserDefaults.standard.bool(forKey: "ndprofile.adhd")
        profileAutism = UserDefaults.standard.object(forKey: "ndprofile.autism") == nil
            ? true : UserDefaults.standard.bool(forKey: "ndprofile.autism")
        profileAUDHD  = UserDefaults.standard.bool(forKey: "ndprofile.audhd")
        profilePTSD   = UserDefaults.standard.bool(forKey: "ndprofile.ptsd")
        profileCPTSD  = UserDefaults.standard.bool(forKey: "ndprofile.cptsd")
        syncProfileSettings()
        let storedLevel = sharedDefaults.string(forKey: rewriteLevelKey) ?? "Medium"
        rewriteLevel = ["Light", "Medium", "Strong"].contains(storedLevel) ? storedLevel : "Medium"
        spiralPauseEnabled = sharedDefaults.object(forKey: spiralPauseEnabledKey) == nil
            ? true : sharedDefaults.bool(forKey: spiralPauseEnabledKey)
        if sharedDefaults.object(forKey: spiralPauseEnabledKey) == nil {
            sharedDefaults.set(true, forKey: spiralPauseEnabledKey)
        }
        let storedSens = sharedDefaults.string(forKey: spiralSensitivityKey) ?? "Medium"
        spiralSensitivity = sensitivities.contains(storedSens) ? storedSens : "Medium"
        showExplanation = true
        if sharedDefaults.object(forKey: showExplanationKey) != nil {
            showExplanation = sharedDefaults.bool(forKey: showExplanationKey)
        } else {
            sharedDefaults.set(true, forKey: showExplanationKey)
        }
        outcomesOptIn = sharedDefaults.bool(forKey: outcomesOptInKey)
    }

    private func saveLevel(_ l: String) {
        rewriteLevel = l
        sharedDefaults.set(l, forKey: rewriteLevelKey)
    }

    private var hasComposerOutput: Bool {
        !composerOriginal.isEmpty || !composerGrammar.isEmpty || !composerNT.isEmpty
    }

    private var selectedComposerText: String {
        switch selectedOutput {
        case "Original":     return composerOriginal
        case "Grammar only": return composerGrammar.isEmpty ? composerOriginal : composerGrammar
        default:
            if !composerNT.isEmpty       { return composerNT }
            if !composerGrammar.isEmpty  { return composerGrammar }
            return composerOriginal
        }
    }

    private var composerResultWindowText: String {
        guard hasComposerOutput else { return "Rewrite result will appear here." }
        return selectedComposerText.isEmpty ? "Rewrite result will appear here." : selectedComposerText
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else {
            composerStatus = "Clipboard is empty"; return
        }
        testText = pasted
        composerStatus = "Pasted \(pasted.count) characters"
        trackOutcome(event: "paste_from_clipboard", inputLength: pasted.count)
    }

    private func copyComposerResult() {
        UIPasteboard.general.string = selectedComposerText
        composerStatus = "Copied \(selectedOutput)"
        trackOutcome(event: "copy_result")
    }

    private func replaceDraftWithResult() {
        testText = selectedComposerText
        sharedDefaults.set(testText, forKey: "testBoxFullText")
        sharedDefaults.synchronize()
        composerStatus = "Draft replaced with \(selectedOutput)"
        trackOutcome(event: "replace_draft")
    }

    private func shareComposerResult() {
        activityItems = [selectedComposerText]
        showingExportSheet = true
        composerStatus = "Choose where to share"
        trackOutcome(event: "share_result")
    }

    private func rewriteComposer() {
        let input = testText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isComposerRewriting = true
        composerStatus = "Rewriting \(input.count) characters..."
        composerOriginal = input
        composerGrammar = ""
        composerNT = ""
        composerExplanation = ""
        selectedOutput = "NT version"
        feedbackSubmitted = false
        Task {
            do {
                let result = try await callServer(text: input)
                await MainActor.run {
                    composerGrammar     = result.grammarOnly.isEmpty ? input : result.grammarOnly
                    composerNT          = result.rewrite
                    composerExplanation = result.explanation
                    isComposerRewriting = false
                    composerStatus      = "Ready"
                    saveLog(original: input, rewritten: result.rewrite, explanation: result.explanation, distortions: result.distortions)
                    trackOutcome(event: "rewrite_completed", inputLength: input.count, outputLength: result.rewrite.count,
                                 distortions: result.distortions, correctionMetrics: CorrectionMetrics(original: input, rewritten: result.rewrite))
                    loadLog()
                }
            } catch {
                await MainActor.run { isComposerRewriting = false; composerStatus = error.localizedDescription }
            }
        }
    }

    private struct ComposerResult {
        let rewrite: String
        let grammarOnly: String
        let explanation: String
        let distortions: [String]
    }

    private func callServer(text: String) async throws -> ComposerResult {
        var req = URLRequest(url: URL(string: serverURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken, forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text":    text,
            "profile": activeProfileLabel,
            "level":   rewriteLevel,
            "mode":    "tonelayer"
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ComposerError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJSON["error"] as? String {
                throw ComposerError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw ComposerError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ComposerError.badResponse }
        let rewrite: String
        if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
            rewrite = paras.joined(separator: "\n\n")
        } else {
            rewrite = parsed["rewrite"] as? String ?? ""
        }
        guard !rewrite.isEmpty else { throw ComposerError.badResponse }
        return ComposerResult(
            rewrite:     rewrite,
            grammarOnly: parsed["grammar_only"] as? String ?? "",
            explanation: parsed["explanation"]  as? String ?? "",
            distortions: parsed["distortions"]  as? [String] ?? []
        )
    }

    private func saveLog(original: String, rewritten: String, explanation: String, distortions: [String]) {
        let entry = RewriteEntry(id: UUID(), timestamp: Date(), profile: activeProfileLabel, mode: rewriteLevel,
                                 originalText: original, rewrittenText: rewritten,
                                 explanation: explanation, distortions: distortions, spiraling: !distortions.isEmpty)
        DispatchQueue.global(qos: .background).async { LogStore.shared.append(entry) }
    }

    private func loadOutcomeEvents() {
        DispatchQueue.global(qos: .background).async {
            let events = OutcomeStore.shared.load()
            DispatchQueue.main.async { outcomeEvents = events }
        }
    }

    private func trackOutcome(event: String, inputLength: Int? = nil, outputLength: Int? = nil,
                              distortions: [String] = [], correctionMetrics: CorrectionMetrics? = nil,
                              feedbackLabel: String? = nil, clarity: Int? = nil, overwhelm: Int? = nil) {
        guard outcomesOptIn else { return }
        let ev = OutcomeEvent(id: UUID(), timestamp: Date(), event: event,
                             inputLength: inputLength ?? 0, outputLength: outputLength ?? 0,
                             distortions: distortions, correctionMetrics: correctionMetrics,
                             feedbackLabel: feedbackLabel, clarity: clarity, overwhelm: overwhelm)
        DispatchQueue.global(qos: .background).async { OutcomeStore.shared.append(ev) }
    }

    private func submitFeedback(label: String, clarity: Int, overwhelm: Int) {
        feedbackSubmitted = true
        trackOutcome(event: "feedback_submitted", feedbackLabel: label, clarity: clarity, overwhelm: overwhelm)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rewrite Log", systemImage: "list.clipboard").font(.title3.weight(.semibold))
                Spacer()
                if !logEntries.isEmpty { Button("Export") { exportLog() }.font(.subheadline) }
            }
            if logEntries.isEmpty {
                Text("No rewrites yet. Use the Composer to generate your first entry.")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(logEntries.suffix(5).reversed()) { entry in logRow(entry) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandViolet)
    }

    private func logRow(_ entry: RewriteEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.profile).font(.caption.weight(.semibold)).foregroundStyle(Color.brandVioletDark)
                Text("\u{2022}").font(.caption).foregroundStyle(.secondary)
                Text(entry.mode).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(entry.originalText.prefix(80)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(10).background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadLog() {
        DispatchQueue.global(qos: .background).async {
            let entries = LogStore.shared.load()
            DispatchQueue.main.async { logEntries = entries }
        }
    }

    private func exportLog() {
        DispatchQueue.global(qos: .background).async {
            let entries = LogStore.shared.load()
            let lines = entries.map { "\($0.timestamp)\t\($0.profile)\t\($0.mode)\t\($0.originalText.replacingOccurrences(of: "\n", with: " "))\t\($0.rewrittenText.replacingOccurrences(of: "\n", with: " "))" }
            let csv = (["Timestamp\tProfile\tMode\tOriginal\tRewritten"] + lines).joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tonelayer_log.tsv")
            try? csv.data(using: .utf8)?.write(to: url)
            DispatchQueue.main.async { activityItems = [url]; showingExportSheet = true }
        }
    }
}

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

enum ComposerError: LocalizedError {
    case apiFailed(Int); case apiMessage(String); case badResponse
    var errorDescription: String? {
        switch self {
        case .apiFailed(let c):  return "Server error (HTTP \(c))"
        case .apiMessage(let m): return m
        case .badResponse:       return "Unexpected server response"
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct UIKitTextView: UIViewRepresentable {
    @Binding var text: String
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.delegate = context.coordinator
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.text = text
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) { if uiView.text != text { uiView.text = text } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UIKitTextView
        init(_ parent: UIKitTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
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

#Preview { ContentView() }
