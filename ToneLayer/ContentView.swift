//
//  ContentView.swift
//  ToneLayer
//
//  Created by Alden-Edwin Lougee on 5/3/26.
//

import SwiftUI
import UIKit

extension Color {
    static let brandVioletDark = Color(red: 0.04, green: 0.06, blue: 0.22)
    static let brandViolet = Color(red: 0.02, green: 0.23, blue: 0.98)
    static let brandGreen = Color(red: 0.06, green: 0.72, blue: 0.70)
    static let brandWhite = Color(red: 0.97, green: 0.98, blue: 0.98)
    static let brandGreenMist = Color(red: 0.93, green: 0.98, blue: 0.98)
    static let brandVioletMist = Color(red: 0.93, green: 0.91, blue: 1.0)
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

    @State private var selectedProfile     = "Autism"
    @State private var rewriteLevel        = "Medium"
    @State private var apiKey              = ""
    @State private var testText            = ""
    @State private var apiKeySaved         = false
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

    private let sensitivities = ["Low", "Medium", "High"]
    private let outputTabs = ["Original", "Grammar only", "NT version"]

    private let profiles = [
        "Autism", "ADHD", "PTSD / CPTSD", "PTSD + Autism", "PTSD + ADHD",
    ]

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
    private let apiKeyKey               = "claudeAPIKey"
    private let spiralPauseEnabledKey   = "spiralPauseEnabled"
    private let spiralSensitivityKey    = "spiralSensitivity"
    private let showExplanationKey      = "showExplanation"
    private let outcomesOptInKey        = "outcomesOptIn"

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                dailyTipCard
                composerCard
                settingsSection
                logCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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

    // MARK: - Header

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

            Text("Dump the messy version here. ToneLayer turns it into NT-readable communication.")
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
                    Text("Type or paste the brain dump...")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Button { pasteFromClipboard() } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    testText = ""
                    composerOriginal = ""
                    composerGrammar = ""
                    composerNT = ""
                    composerExplanation = ""
                    composerStatus = ""
                    feedbackSubmitted = false
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(testText.isEmpty)
            }

            Button(action: rewriteComposer) {
                HStack {
                    if isComposerRewriting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isComposerRewriting ? "Rewriting..." : "Rewrite")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isComposerRewriting || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.brandGreen.opacity(0.45) : Color.brandGreen)
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

            Text(composerResultWindowText)
                .font(.body)
                .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding(14)
                .background(Color.brandGreenMist)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                Label("Teaching explanation", systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandGreen)
                Text(composerTeachingWindowText)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .padding(14)
            .background(Color.brandGreenMist)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if hasComposerOutput {
                HStack(spacing: 10) {
                    Button { copyComposerResult() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandGreen)

                    Button { replaceDraftWithResult() } label: {
                        Label("Replace Draft", systemImage: "arrow.uturn.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if outcomesOptIn {
                    feedbackCard
                }
            }

            Button { shareComposerResult() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandVioletDark)
            .disabled(!hasComposerOutput)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private var settingsSection: some View {
        DisclosureGroup {
            VStack(spacing: 20) {
                apiKeyCard
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

    // MARK: - API Key

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Claude API Key", systemImage: "key.fill")
                .font(.title3.weight(.semibold))

            Text("Your key is stored securely in the app group so the keyboard can use it. Get yours at console.anthropic.com.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            SecureField("sk-ant-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                saveAPIKey()
            } label: {
                HStack {
                    Image(systemName: apiKeySaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                    Text(apiKeySaved ? "Saved!" : "Save Key")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(apiKeySaved ? Color.brandGreen : Color.brandVioletDark)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    // MARK: - Privacy / Outcomes

    private var privacyAndOutcomesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Personalization & Outcomes", systemImage: "lock.shield")
                .font(.title3.weight(.semibold))

            Text("Optional consent for using ADHD evaluation data and ToneLayer activity patterns to personalize support and measure whether the tools are helping.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use my data to personalize support")
                        .font(.subheadline.weight(.semibold))
                    Text("When this is off, ToneLayer should only use local settings needed for the current rewrite. This is not emergency monitoring.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $outcomesOptIn)
                    .labelsHidden()
                    .onChange(of: outcomesOptIn) { _, newValue in
                        sharedDefaults.set(newValue, forKey: outcomesOptInKey)
                    }
            }

            Text("Future payer or clinical reports should require this opt-in and should show function-level outcomes, not private draft text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private var outcomesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Local Outcomes", systemImage: "chart.bar.xaxis")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(outcomesOptIn ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcomesOptIn ? .green : .secondary)
            }

            if !outcomesOptIn {
                Text("Turn on Personalization & Outcomes to collect local event summaries. Draft text is not stored in these summaries.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if outcomeEvents.isEmpty {
                Text("No local outcome events yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let rewrites = outcomeEvents.filter { $0.event == "rewrite_completed" }.count
                let exports = outcomeEvents.filter { $0.event.hasPrefix("export_") || $0.event == "copy_result" }.count
                let feedback = outcomeEvents.filter { $0.event == "feedback_submitted" }.count
                let latest = outcomeEvents.suffix(30)
                let averageInput = latest.isEmpty ? 0 : latest.map(\.inputLength).reduce(0, +) / latest.count
                let correctionScores = outcomeEvents.compactMap { $0.correctionMetrics?.changeScore }
                let averageCorrection = correctionScores.isEmpty ? 0 : correctionScores.reduce(0, +) / correctionScores.count

                VStack(spacing: 8) {
                    outcomeRow("Tracked events", "\(outcomeEvents.count)")
                    outcomeRow("Rewrites", "\(rewrites)")
                    outcomeRow("Copy/export actions", "\(exports)")
                    outcomeRow("Survey responses", "\(feedback)")
                    outcomeRow("Avg recent input", "\(averageInput) chars")
                    outcomeRow("Avg correction depth", "\(averageCorrection)%")
                }

                Button("Clear Local Outcomes") {
                    OutcomeStore.shared.clear()
                    outcomeEvents = []
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private func outcomeRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    // MARK: - Profile Picker

    private let profileDescriptions: [String: String] = [
        "Autism":        "Add warmth · Decode · Literalize · Tone-tag",
        "ADHD":          "Tighten · Add structure · Cut tangents",
        "PTSD / CPTSD":  "De-escalate · Boundary set · Decompress",
        "PTSD + Autism": "Blended modes for both profiles",
        "PTSD + ADHD":   "Blended modes for both profiles",
    ]

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Profile", systemImage: "person.crop.circle")
                .font(.title3.weight(.semibold))

            Text("Pick the profile that matches how you communicate. Combo profiles blend techniques from both.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(profiles, id: \.self) { profile in
                    Button {
                        saveProfile(profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(selectedProfile == profile ? Color(red: 0.12, green: 0.15, blue: 0.18) : Color.primary)
                                Spacer()
                                if selectedProfile == profile {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.brandVioletDark)
                                }
                            }
                            if let desc = profileDescriptions[profile] {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(selectedProfile == profile ? Color(red: 0.30, green: 0.34, blue: 0.38) : Color.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedProfile == profile
                                ? Color.brandVioletMist
                                : Color(.tertiarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    // MARK: - Level Picker

    private let levelDescriptions: [String: String] = [
        "Light":  "Small ND-to-NT adjustments: fixes clarity, grammar, and tone while keeping your wording close.",
        "Medium": "Balanced ND-to-NT rewrite: restructures the message for NT readers while still sounding like you.",
        "Strong": "Full ND-to-NT translation: concise, direct, emotionally neutral, and easy for NT readers to act on.",
    ]

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("NT Level", systemImage: "sparkles")
                .font(.title3.weight(.semibold))

            Text("Choose how strongly ToneLayer should translate ND speech into NT speech. Start at Medium and compare all three levels to learn the patterns.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            VStack(spacing: 10) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                    Button {
                        saveLevel(l)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(rewriteLevel == l ? Color(red: 0.12, green: 0.15, blue: 0.18) : Color.primary)
                                if let desc = levelDescriptions[l] {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(rewriteLevel == l ? Color(red: 0.30, green: 0.34, blue: 0.38) : Color.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if rewriteLevel == l {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brandVioletDark)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            rewriteLevel == l
                                ? Color.brandVioletMist
                                : Color(.tertiarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    // MARK: - Spiral Pause

    private var spiralPauseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Spiral Pause", systemImage: "heart.circle")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: $spiralPauseEnabled)
                    .labelsHidden()
                    .onChange(of: spiralPauseEnabled) { _, newValue in
                        sharedDefaults.set(newValue, forKey: spiralPauseEnabledKey)
                    }
            }

            Text("Before rewriting, ToneLayer checks if your text shows cognitive distortions (catastrophizing, all-or-nothing, mind-reading, etc.). If it does, it pauses and offers a calmer draft. You can always override and send your original.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            if spiralPauseEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity")
                        .font(.subheadline.weight(.medium))
                    Picker("Sensitivity", selection: $spiralSensitivity) {
                        ForEach(sensitivities, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: spiralSensitivity) { _, newValue in
                        sharedDefaults.set(newValue, forKey: spiralSensitivityKey)
                    }

                    Text(sensitivityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    // MARK: - Explanation Toggle

    private var explanationToggleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Teaching Explanations", systemImage: "lightbulb")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: $showExplanation)
                    .labelsHidden()
                    .onChange(of: showExplanation) { _, newValue in
                        sharedDefaults.set(newValue, forKey: showExplanationKey)
                    }
            }
            Text("Show a short note explaining what changed and why. Turn this off when you only want the rewrite.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private var sensitivityDescription: String {
        switch spiralSensitivity {
        case "Low":  return "Only pauses on strong signals (clear panic, multiple heavy distortions)."
        case "High": return "Pauses on any clear distortion. May feel intrusive."
        default:     return "Pauses when two or more distortions are present. Recommended."
        }
    }

    // MARK: - Test Area

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keyboard Test", systemImage: "keyboard")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !testText.isEmpty {
                    Button("Clear") { testText = "" }
                        .font(.subheadline)
                }
            }

            Text("Type or paste anything in the box below — a brain dump, a draft text, whatever. Switch to ToneLayer Keyboard (globe key), tap ✶ Rewrite. The rewrite replaces the text in this same box.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $testText)
                    .frame(minHeight: 180, maxHeight: 320)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )

                if testText.isEmpty {
                    Text("Type or paste your text here…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Text("\(testText.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Status", systemImage: "checkmark.seal")
                .font(.title3.weight(.semibold))

            statusRow(title: "Host app",              value: "✓ Running")
            statusRow(title: "Keyboard extension",    value: "✓ Installed")
            statusRow(title: "API key",               value: apiKey.isEmpty ? "Not set" : "✓ Set")
            statusRow(title: "Active profile",        value: selectedProfile)
            statusRow(title: "NT level",               value: rewriteLevel)
            statusRow(title: "App group sharing",     value: "✓ Enabled")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let raw = sharedDefaults.string(forKey: selectedProfileKey) ?? "Autism"
        let storedProfile = raw == "PTSD" ? "PTSD / CPTSD" : raw
        selectedProfile = profiles.contains(storedProfile) ? storedProfile : "Autism"

        let storedLevel = sharedDefaults.string(forKey: rewriteLevelKey) ?? "Medium"
        rewriteLevel = ["Light", "Medium", "Strong"].contains(storedLevel) ? storedLevel : "Medium"

        apiKey = sharedDefaults.string(forKey: apiKeyKey) ?? ""

        if sharedDefaults.object(forKey: spiralPauseEnabledKey) == nil {
            spiralPauseEnabled = true
            sharedDefaults.set(true, forKey: spiralPauseEnabledKey)
        } else {
            spiralPauseEnabled = sharedDefaults.bool(forKey: spiralPauseEnabledKey)
        }
        let storedSens = sharedDefaults.string(forKey: spiralSensitivityKey) ?? "Medium"
        spiralSensitivity = sensitivities.contains(storedSens) ? storedSens : "Medium"
        if spiralSensitivity == "Light" { spiralSensitivity = "Low" }
        if spiralSensitivity == "Strong" { spiralSensitivity = "High" }

        if sharedDefaults.object(forKey: showExplanationKey) == nil {
            showExplanation = true
            sharedDefaults.set(true, forKey: showExplanationKey)
        } else {
            showExplanation = sharedDefaults.bool(forKey: showExplanationKey)
        }

        outcomesOptIn = sharedDefaults.bool(forKey: outcomesOptInKey)
    }

    private func saveProfile(_ profile: String) {
        selectedProfile = profile
        sharedDefaults.set(profile, forKey: selectedProfileKey)
    }

    private func saveLevel(_ l: String) {
        rewriteLevel = l
        sharedDefaults.set(l, forKey: rewriteLevelKey)
    }

    private func saveAPIKey() {
        sharedDefaults.set(apiKey, forKey: apiKeyKey)
        apiKeySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            apiKeySaved = false
        }
    }

    // MARK: - Composer Actions

    private var hasComposerOutput: Bool {
        !composerOriginal.isEmpty || !composerGrammar.isEmpty || !composerNT.isEmpty
    }

    private var selectedComposerText: String {
        switch selectedOutput {
        case "Original": return composerOriginal
        case "Grammar only": return composerGrammar.isEmpty ? composerOriginal : composerGrammar
        default:
            if !composerNT.isEmpty { return composerNT }
            if !composerGrammar.isEmpty { return composerGrammar }
            return composerOriginal
        }
    }

    private var composerResultWindowText: String {
        guard hasComposerOutput else { return "Rewrite result will appear here." }
        return selectedComposerText.isEmpty ? "Rewrite result will appear here." : selectedComposerText
    }

    private var composerTeachingWindowText: String {
        guard showExplanation else { return "Teaching explanations are turned off in Options." }
        guard hasComposerOutput else { return "After a rewrite, this will explain what changed and why the result is more NT-readable." }
        return composerExplanation.isEmpty ? "No teaching explanation returned for this rewrite." : composerExplanation
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else {
            composerStatus = "Clipboard is empty"
            return
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
        guard !apiKey.isEmpty else {
            composerStatus = "Add your Claude API key in Settings first"
            return
        }

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
                let result = try await callClaudeForComposer(text: input)
                await MainActor.run {
                    composerGrammar = result.grammarOnly.isEmpty ? input : result.grammarOnly
                    composerNT = result.rewrite
                    composerExplanation = result.explanation
                    isComposerRewriting = false
                    composerStatus = "Ready"
                    saveLog(
                        original: input,
                        rewritten: result.rewrite,
                        explanation: result.explanation,
                        distortions: result.distortions
                    )
                    trackOutcome(
                        event: "rewrite_completed",
                        inputLength: input.count,
                        outputLength: result.rewrite.count,
                        distortions: result.distortions,
                        correctionMetrics: CorrectionMetrics(original: input, rewritten: result.rewrite)
                    )
                    loadLog()
                }
            } catch {
                await MainActor.run {
                    isComposerRewriting = false
                    composerStatus = error.localizedDescription
                }
            }
        }
    }

    private struct ComposerResult {
        let rewrite: String
        let grammarOnly: String
        let explanation: String
        let distortions: [String]
    }

    private func callClaudeForComposer(text: String) async throws -> ComposerResult {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 8192,
            "system": buildComposerSystem(),
            "messages": [["role": "user", "content": "Text:\n\(text)\n\nReply with ONLY valid JSON."]],
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ComposerError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = errJSON["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw ComposerError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw ComposerError.apiFailed(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String
        else { throw ComposerError.badResponse }

        let cleaned = extractComposerJSON(from: content)
        guard let parsedData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: parsedData) as? [String: Any]
        else {
            return ComposerResult(rewrite: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), grammarOnly: "", explanation: "", distortions: [])
        }

        let rewrite: String
        if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
            rewrite = paras.joined(separator: "\n\n")
        } else {
            rewrite = parsed["rewrite"] as? String ?? ""
        }

        guard !rewrite.isEmpty else { throw ComposerError.badResponse }
        return ComposerResult(
            rewrite: rewrite,
            grammarOnly: parsed["grammar_only"] as? String ?? "",
            explanation: parsed["explanation"] as? String ?? "",
            distortions: parsed["distortions"] as? [String] ?? []
        )
    }

    private func buildComposerSystem() -> String {
        """
        You are ToneLayer, a communication assistant that translates neurodivergent brain dumps into neurotypical-readable communication for a \(selectedProfile) user.

        Rewrite the entire text from ND speech into NT-readable speech at the \(rewriteLevel) level. Preserve the user's intended message, requests, constraints, and necessary context from the whole original. Follow the selected rewrite level exactly.

        Light: small ND-to-NT adjustments; fix clarity, grammar, and tone while keeping wording close.
        Medium: balanced ND-to-NT rewrite; structure the message for NT readers while still sounding like the user.
        Strong: full ND-to-NT translation; concise, direct, emotionally neutral, low-friction for the reader, main point first, support need named when possible. Remove spirals, repeated urgency, metaphors, side quests, and internal processing unless they are strictly necessary.

        The "paragraphs" rewrite is the primary output. Do not shorten or flatten it to make room for grammar_only.

        Always respond with ONLY valid JSON:
        {
          "paragraphs": ["rewritten paragraph one", "rewritten paragraph two"],
          "explanation": "one sentence explaining what changed and why it is more NT-readable",
          "distortions": ["any cognitive distortions found, empty array if none"],
          "grammar_only": "grammar-fixed version of the full original that keeps the user's ND structure and meaning"
        }
        """
    }

    private func extractComposerJSON(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNL = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNL)...]) }
            if s.hasSuffix("```") { s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if let openIdx = s.firstIndex(of: "{"), let closeIdx = s.lastIndex(of: "}"), openIdx < closeIdx {
            return String(s[openIdx...closeIdx])
        }
        return s
    }

    private func saveLog(original: String, rewritten: String, explanation: String, distortions: [String]) {
        let entry = RewriteEntry(
            id: UUID(), timestamp: Date(),
            profile: selectedProfile, mode: rewriteLevel,
            originalText: original, rewrittenText: rewritten,
            explanation: explanation, distortions: distortions, spiraling: !distortions.isEmpty
        )
        DispatchQueue.global(qos: .background).async { LogStore.shared.append(entry) }
    }

    private func loadOutcomeEvents() {
        DispatchQueue.global(qos: .background).async {
            let events = OutcomeStore.shared.load()
            DispatchQueue.main.async { outcomeEvents = events }
        }
    }

    private func trackOutcome(
        event: String,
        inputLength: Int? = nil,
        outputLength: Int? = nil,
        distortions: [String] = [],
        correctionMetrics: CorrectionMetrics? = nil,
        feedbackLabel: String? = nil,
        clarityRating: Int? = nil,
        overwhelmRating: Int? = nil
    ) {
        guard outcomesOptIn else { return }
        let entry = OutcomeEvent(
            id: UUID(), timestamp: Date(),
            event: event, profile: selectedProfile, mode: rewriteLevel,
            selectedOutput: selectedOutput,
            inputLength: inputLength ?? testText.count,
            outputLength: outputLength ?? selectedComposerText.count,
            correctionMetrics: correctionMetrics,
            distortions: distortions,
            feedbackLabel: feedbackLabel,
            clarityRating: clarityRating,
            overwhelmRating: overwhelmRating
        )
        DispatchQueue.global(qos: .background).async {
            OutcomeStore.shared.append(entry)
            let events = OutcomeStore.shared.load()
            DispatchQueue.main.async { outcomeEvents = events }
        }
    }

    private func submitFeedback(label: String, clarity: Int, overwhelm: Int) {
        trackOutcome(event: "feedback_submitted", feedbackLabel: label, clarityRating: clarity, overwhelmRating: overwhelm)
        feedbackSubmitted = true
        composerStatus = "Feedback saved locally"
    }

    // MARK: - Log

    private func loadLog() {
        DispatchQueue.global(qos: .background).async {
            let entries = LogStore.shared.load()
            DispatchQueue.main.async { logEntries = entries }
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rewrite Log", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !logEntries.isEmpty {
                    Text("\(logEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if logEntries.isEmpty {
                Text("Your rewrite history will appear here after your first rewrite from the keyboard.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                let patterns = LogStore.shared.topPatterns()
                if !patterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recurring patterns")
                            .font(.subheadline.weight(.semibold))
                        ForEach(patterns, id: \.pattern) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(patternDotColor(item.count))
                                    .frame(width: 9, height: 9)
                                Text(item.pattern)
                                Spacer()
                                Text("\(item.count)× in recent rewrites")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Divider()
                }

                ForEach(logEntries.suffix(10).reversed(), id: \.id) { entry in
                    logRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private func logRow(_ entry: RewriteEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.profile)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.brandVioletDark.opacity(0.12))
                    .clipShape(Capsule())
                Text("·").foregroundStyle(.tertiary)
                Text(entry.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !entry.explanation.isEmpty {
                Text(entry.explanation).font(.subheadline)
            }
            Text(entry.rewrittenText.prefix(100) + (entry.rewrittenText.count > 100 ? "…" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func patternDotColor(_ count: Int) -> Color {
        count >= 6 ? .red : count >= 4 ? .orange : .yellow
    }
}

#Preview {
    ContentView()
}

enum ComposerError: LocalizedError {
    case apiFailed(Int)
    case apiMessage(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .apiFailed(let code): return "API failed (HTTP \(code))"
        case .apiMessage(let message): return message
        case .badResponse: return "Unexpected API response"
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

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UIKitTextView
        private var pendingWrite: DispatchWorkItem?
        init(_ parent: UIKitTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            pendingWrite?.cancel()
            let snapshot = textView.text ?? ""
            let shared = UserDefaults(suiteName: "group.com.alden.tonelayer")
            guard shared?.bool(forKey: "keyboardRewriteInProgress") != true else { return }
            shared?.set(snapshot, forKey: "testBoxFullText")
            let work = DispatchWorkItem { shared?.synchronize() }
            pendingWrite = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Rewrite log

struct RewriteEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let profile: String
    let mode: String
    let originalText: String
    let rewrittenText: String
    let explanation: String
    let distortions: [String]
    let spiraling: Bool
}

final class LogStore {
    static let shared = LogStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "rewrite_log.json"

    private var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    func load() -> [RewriteEntry] {
        guard let url = logURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RewriteEntry].self, from: data)
        else { return [] }
        return entries
    }

    func append(_ entry: RewriteEntry) {
        var entries = load()
        entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func topPatterns(limit: Int = 40) -> [(pattern: String, count: Int)] {
        let recent = Array(load().suffix(limit))
        let all = recent.flatMap { $0.distortions }.filter { !$0.isEmpty }
        return Dictionary(grouping: all, by: { $0 })
            .mapValues { $0.count }
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (pattern: $0.key, count: $0.value) }
    }
}

struct OutcomeEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let event: String
    let profile: String
    let mode: String
    let selectedOutput: String
    let inputLength: Int
    let outputLength: Int
    let correctionMetrics: CorrectionMetrics?
    let distortions: [String]
    let feedbackLabel: String?
    let clarityRating: Int?
    let overwhelmRating: Int?
}

struct CorrectionMetrics: Codable {
    let lengthDelta: Int
    let originalWordCount: Int
    let rewrittenWordCount: Int
    let originalSentenceCount: Int
    let rewrittenSentenceCount: Int
    let originalParagraphCount: Int
    let rewrittenParagraphCount: Int
    let wordOverlapPercent: Int
    let compressionPercent: Int
    let changeScore: Int

    init(original: String, rewritten: String) {
        let originalWords = Self.words(in: original)
        let rewrittenWords = Self.words(in: rewritten)
        let originalSet = Set(originalWords)
        let rewrittenSet = Set(rewrittenWords)
        let overlap = originalSet.isEmpty ? 0 : originalSet.intersection(rewrittenSet).count * 100 / originalSet.count
        let compression = originalWords.isEmpty ? 0 : max(0, (originalWords.count - rewrittenWords.count) * 100 / originalWords.count)
        let sentenceDelta = abs(Self.sentenceCount(in: original) - Self.sentenceCount(in: rewritten))
        let paragraphDelta = abs(Self.paragraphCount(in: original) - Self.paragraphCount(in: rewritten))
        let overlapChange = 100 - overlap

        lengthDelta = rewritten.count - original.count
        originalWordCount = originalWords.count
        rewrittenWordCount = rewrittenWords.count
        originalSentenceCount = Self.sentenceCount(in: original)
        rewrittenSentenceCount = Self.sentenceCount(in: rewritten)
        originalParagraphCount = Self.paragraphCount(in: original)
        rewrittenParagraphCount = Self.paragraphCount(in: rewritten)
        wordOverlapPercent = overlap
        compressionPercent = compression
        changeScore = min(100, max(0, (overlapChange + compression + min(30, sentenceDelta * 5) + min(20, paragraphDelta * 5)) / 2))
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 }
    }
    private static func sentenceCount(in text: String) -> Int {
        max(1, text.split { ".!?".contains($0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
    }
    private static func paragraphCount(in text: String) -> Int {
        max(1, text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
    }
}

final class OutcomeStore {
    static let shared = OutcomeStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName = "outcome_events.json"

    private var eventsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    func load() -> [OutcomeEvent] {
        guard let url = eventsURL,
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([OutcomeEvent].self, from: data)
        else { return [] }
        return events
    }

    func append(_ event: OutcomeEvent) {
        var events = load()
        events.append(event)
        if events.count > 1000 { events = Array(events.suffix(1000)) }
        guard let url = eventsURL, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let url = eventsURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
