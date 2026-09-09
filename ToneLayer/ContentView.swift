// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

//
//  ContentView.swift
//  ToneLayer
//
//  Created by Alden-Edwin Lougee on 5/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appModel = AppModel()
    @StateObject private var hume = HumeEVIClient()
    @StateObject private var schedule = ScheduleProvider()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = "compose"

    var body: some View {
        TabView(selection: $selectedTab) {
            ComposerView()
                .tabItem { Label("Compose", systemImage: "square.and.pencil") }
                .tag("compose")
            DecoderView()
                .tabItem { Label("Decode", systemImage: "eye.circle.fill") }
                .tag("decode")
            InsightView()
                .tabItem { Label("TonalInsight", systemImage: "waveform") }
                .tag("insight")
            PlanView()
                .tabItem { Label("Plan", systemImage: "checklist") }
                .tag("plan")
            HistoryView()
                .tabItem { Label("History", systemImage: "list.clipboard") }
                .tag("history")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag("settings")
        }
        .environmentObject(appModel)
        .environmentObject(hume)
        .tint(Color.brandVioletDark)
        .onAppear {
            appModel.loadSettings()
            appModel.loadLog()
            appModel.loadOutcomeEvents()
            Task {
                await schedule.refresh()
                hume.scheduleContext = schedule.agendaText
            }
            applyRequestedTabIfAny()
        }
        .onChange(of: schedule.agendaText) { _, newValue in
            hume.scheduleContext = newValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { applyRequestedTabIfAny() }
        }
        .sheet(isPresented: $appModel.showingExportSheet) {
            ActivityView(activityItems: appModel.activityItems)
        }
    }

    /// Set by `OpenTonalInsightIntent` (Siri/Shortcuts) via the app-group
    /// defaults, since an App Intent runs out-of-process and can't hold a
    /// direct reference to this view's own `selectedTab` state — checked
    /// on every appear/foreground rather than only once at launch, since
    /// the intent can fire while the app is already running in the
    /// background.
    private func applyRequestedTabIfAny() {
        guard let requested = appModel.sharedDefaults.string(forKey: "requestedTab") else { return }
        selectedTab = requested
        appModel.sharedDefaults.removeObject(forKey: "requestedTab")
    }
}

#Preview { ContentView() }
