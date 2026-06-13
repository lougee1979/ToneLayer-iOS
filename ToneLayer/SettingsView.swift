// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject var appModel: AppModel

    private let levelDescriptions: [String: String] = [
        "Light":  "Small ND-to-NT adjustments: fixes clarity, grammar, and tone while keeping your wording close.",
        "Medium": "Balanced ND-to-NT rewrite: restructures the message for NT readers while still sounding like you.",
        "Strong": "Full ND-to-NT translation: concise, direct, emotionally neutral, and easy for NT readers to act on.",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileCard
                levelCard
                spiralPauseCard
                explanationToggleCard
                privacyAndOutcomesCard
                analyticsCard
                testCard
                statusCard
            }
            .padding()
        }
        .appBackground()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ND Profile", systemImage: "person.crop.circle").font(.title3.weight(.semibold))
            Text("Check all that apply. AUDHD = ADHD + Autism combined.")
                .foregroundStyle(.secondary).font(.subheadline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                profileCheckbox("ADHD",   isOn: $appModel.profileADHD)
                profileCheckbox("Autism", isOn: $appModel.profileAutism)
                profileCheckbox("AUDHD",  isOn: $appModel.profileAUDHD)
                profileCheckbox("PTSD",   isOn: $appModel.profilePTSD)
                profileCheckbox("CPTSD",  isOn: $appModel.profileCPTSD)
            }
            if appModel.activeProfileLabel != "General ND" {
                Label("Active: \(appModel.activeProfileLabel)", systemImage: "checkmark.circle.fill")
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
            appModel.syncProfileSettings()
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

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("NT Level", systemImage: "sparkles").font(.title3.weight(.semibold))
            Text("Choose how strongly ToneLayer should translate ND speech into NT speech.")
                .foregroundStyle(.secondary).font(.subheadline)
            VStack(spacing: 10) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                    Button { appModel.saveLevel(l) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l).fontWeight(.semibold)
                                    .foregroundStyle(appModel.rewriteLevel == l ? Color(red:0.12,green:0.15,blue:0.18) : Color.primary)
                                if let desc = levelDescriptions[l] {
                                    Text(desc).font(.caption)
                                        .foregroundStyle(appModel.rewriteLevel == l ? Color(red:0.30,green:0.34,blue:0.38) : Color.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if appModel.rewriteLevel == l {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brandVioletDark)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(appModel.rewriteLevel == l ? Color.brandVioletMist : Color(.tertiarySystemBackground))
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
                Toggle("", isOn: $appModel.spiralPauseEnabled).labelsHidden()
                    .onChange(of: appModel.spiralPauseEnabled) { _, v in appModel.saveSpiralPauseEnabled(v) }
            }
            Text("Before rewriting, ToneLayer checks if your text shows cognitive distortions. If it does, it pauses and offers a calmer draft.")
                .foregroundStyle(.secondary).font(.subheadline)
            if appModel.spiralPauseEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity").font(.subheadline.weight(.medium))
                    Picker("Sensitivity", selection: $appModel.spiralSensitivity) {
                        ForEach(appModel.sensitivities, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appModel.spiralSensitivity) { _, v in appModel.saveSpiralSensitivity(v) }
                    Text(sensitivityDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandGreen)
    }

    private var sensitivityDescription: String {
        switch appModel.spiralSensitivity {
        case "Low":  return "Only pauses on strong signals."
        case "High": return "Pauses on any clear distortion. May feel intrusive."
        default:     return "Pauses when two or more distortions are present. Recommended."
        }
    }

    private var explanationToggleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Teaching Window", systemImage: "lightbulb").font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: $appModel.showExplanation).labelsHidden()
                    .onChange(of: appModel.showExplanation) { _, v in appModel.saveShowExplanation(v) }
            }
            Text("Shows teaching explanation below every rewrite. Turn it off here if you only want the rewrite output.")
                .foregroundStyle(.secondary).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandVioletDark)
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
                Toggle("", isOn: $appModel.outcomesOptIn).labelsHidden()
                    .onChange(of: appModel.outcomesOptIn) { _, v in appModel.saveOutcomesOptIn(v) }
            }
            Text("Future payer or clinical reports should require this opt-in and should show function-level outcomes, not private draft text.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandGreen)
    }

    private var analyticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Anonymous Usage Analytics", systemImage: "chart.bar.doc.horizontal")
                .font(.title3.weight(.semibold))
            Text("Help show funders and insurers that ToneLayer is helping people \u{2014} without sharing anything about you.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share anonymous usage data").font(.subheadline.weight(.semibold))
                    Text("When on, ToneLayer sends only anonymous counts \u{2014} like how many rewrites you do, your average correction score, and whether you marked outputs helpful. Your message text, contacts, and identity are never included. Each install is tagged with a random ID that isn't linked to you.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $appModel.analyticsOptIn).labelsHidden()
                    .onChange(of: appModel.analyticsOptIn) { _, v in appModel.saveAnalyticsOptIn(v) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: .brandVioletDark)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keyboard Test", systemImage: "keyboard").font(.title3.weight(.semibold))
                Spacer()
                if !appModel.testText.isEmpty { Button("Clear") { appModel.testText = "" }.font(.subheadline) }
            }
            ZStack(alignment: .topLeading) {
                UIKitTextView(text: $appModel.testText)
                    .frame(minHeight: 180, maxHeight: 320).padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5))
                if appModel.testText.isEmpty {
                    Text("Type or paste your text here\u{2026}")
                        .foregroundStyle(.tertiary).font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
            HStack { Spacer(); Text("\(appModel.testText.count) characters").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandVioletDark)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Status", systemImage: "checkmark.seal").font(.title3.weight(.semibold))
            statusRow(title: "Host app",           value: "\u{2713} Running")
            statusRow(title: "Keyboard extension", value: "\u{2713} Installed")
            statusRow(title: "Server",             value: "\u{2713} railway.app")
            statusRow(title: "Active profile",     value: appModel.activeProfileLabel)
            statusRow(title: "NT level",            value: appModel.rewriteLevel)
            statusRow(title: "App group sharing",  value: "\u{2713} Enabled")
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).glassCard(tint: .brandGreen)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.semibold) }
    }
}

#Preview {
    SettingsView().environmentObject(AppModel())
}
