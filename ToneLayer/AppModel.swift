// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation
import Combine

final class AppModel: ObservableObject {

    // Profile (Settings writes; Compose reads via activeProfileLabel)
    @Published var profileADHD   = false
    @Published var profileAutism = true
    @Published var profileAUDHD  = false
    @Published var profilePTSD   = false
    @Published var profileCPTSD  = false

    // Shared settings (Settings tab writes; Compose/History read)
    @Published var rewriteLevel       = "Medium"
    @Published var spiralPauseEnabled = true
    @Published var spiralSensitivity  = "Medium"
    @Published var showExplanation    = true
    @Published var outcomesOptIn      = false
    @Published var analyticsOptIn     = false

    // Cross-tab text buffer: Compose composer <-> Settings testCard <-> Insight sheet callbacks
    @Published var testText = ""

    // History data (Compose writes after rewrite; History displays)
    @Published var logEntries: [RewriteEntry] = []
    @Published var outcomeEvents: [OutcomeEvent] = []

    // Shared export sheet (Compose share button + History export button)
    @Published var activityItems: [Any] = []
    @Published var showingExportSheet = false

    let sensitivities = ["Low", "Medium", "High"]

    private let appGroupID            = "group.com.alden.tonelayer"
    private let selectedProfileKey    = "selectedProfile"
    private let rewriteLevelKey       = "rewriteLevel"
    private let spiralPauseEnabledKey = "spiralPauseEnabled"
    private let spiralSensitivityKey  = "spiralSensitivity"
    private let showExplanationKey    = "showExplanation.v2"
    private let outcomesOptInKey      = "outcomesOptIn"
    private let analyticsOptInKey     = "analyticsOptIn"
    private let analyticsInstallIDKey = "analyticsInstallID"

    var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Random per-install ID, never tied to identity. Generated once and
    /// reused so anonymous usage analytics can be deduplicated by install
    /// without revealing who the install belongs to.
    var anonymousInstallID: String {
        if let existing = sharedDefaults.string(forKey: analyticsInstallIDKey) {
            return existing
        }
        let newID = UUID().uuidString
        sharedDefaults.set(newID, forKey: analyticsInstallIDKey)
        return newID
    }

    var activeProfileLabel: String {
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

    func syncProfileSettings() {
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

    func loadSettings() {
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
        analyticsOptIn = sharedDefaults.bool(forKey: analyticsOptInKey)
    }

    func saveLevel(_ l: String) {
        rewriteLevel = l
        sharedDefaults.set(l, forKey: rewriteLevelKey)
    }

    func saveSpiralPauseEnabled(_ v: Bool) {
        spiralPauseEnabled = v
        sharedDefaults.set(v, forKey: spiralPauseEnabledKey)
    }

    func saveSpiralSensitivity(_ v: String) {
        spiralSensitivity = v
        sharedDefaults.set(v, forKey: spiralSensitivityKey)
    }

    func saveShowExplanation(_ v: Bool) {
        showExplanation = v
        sharedDefaults.set(v, forKey: showExplanationKey)
    }

    func saveOutcomesOptIn(_ v: Bool) {
        outcomesOptIn = v
        sharedDefaults.set(v, forKey: outcomesOptInKey)
    }

    func saveAnalyticsOptIn(_ v: Bool) {
        analyticsOptIn = v
        sharedDefaults.set(v, forKey: analyticsOptInKey)
    }

    func loadLog() {
        DispatchQueue.global(qos: .background).async {
            let entries = LogStore.shared.load()
            DispatchQueue.main.async { self.logEntries = entries }
        }
    }

    func loadOutcomeEvents() {
        DispatchQueue.global(qos: .background).async {
            let events = OutcomeStore.shared.load()
            DispatchQueue.main.async { self.outcomeEvents = events }
        }
    }

    func trackOutcome(event: String, inputLength: Int? = nil, outputLength: Int? = nil,
                      distortions: [String] = [], correctionMetrics: CorrectionMetrics? = nil,
                      feedbackLabel: String? = nil, clarity: Int? = nil, overwhelm: Int? = nil) {
        if analyticsOptIn {
            sendAnalyticsEvent(event: event, inputLength: inputLength ?? 0, outputLength: outputLength ?? 0,
                               distortionCount: distortions.count, correctionScore: correctionMetrics?.changeScore,
                               feedbackLabel: feedbackLabel, clarity: clarity, overwhelm: overwhelm)
        }
        guard outcomesOptIn else { return }
        let ev = OutcomeEvent(id: UUID(), timestamp: Date(), event: event,
                             inputLength: inputLength ?? 0, outputLength: outputLength ?? 0,
                             distortions: distortions, correctionMetrics: correctionMetrics,
                             feedbackLabel: feedbackLabel, clarity: clarity, overwhelm: overwhelm)
        DispatchQueue.global(qos: .background).async { OutcomeStore.shared.append(ev) }
    }

    /// Sends a fully anonymized usage event to the server: a random
    /// per-install ID plus numeric counts/scores only. Never includes
    /// message text, contact names, or anything else identifying.
    private func sendAnalyticsEvent(event: String, inputLength: Int, outputLength: Int,
                                     distortionCount: Int, correctionScore: Int?,
                                     feedbackLabel: String?, clarity: Int?, overwhelm: Int?) {
        guard let url = URL(string: AppConfig.analyticsURL) else { return }
        var payload: [String: Any] = [
            "installId": anonymousInstallID,
            "event": event,
            "inputLength": inputLength,
            "outputLength": outputLength,
            "distortionCount": distortionCount,
        ]
        if let correctionScore { payload["correctionScore"] = correctionScore }
        if let feedbackLabel  { payload["feedbackLabel"] = feedbackLabel }
        if let clarity        { payload["clarity"] = clarity }
        if let overwhelm      { payload["overwhelm"] = overwhelm }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.appToken, forHTTPHeaderField: "x-app-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
}
