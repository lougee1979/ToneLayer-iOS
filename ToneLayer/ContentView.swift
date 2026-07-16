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

    var body: some View {
        TabView {
            ComposerView()
                .tabItem { Label("Compose", systemImage: "square.and.pencil") }
            DecoderView()
                .tabItem { Label("Decode", systemImage: "eye.circle.fill") }
            InsightView()
                .tabItem { Label("TonalInsight", systemImage: "waveform") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "checklist") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.clipboard") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
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
        }
        .onChange(of: schedule.agendaText) { _, newValue in
            hume.scheduleContext = newValue
        }
        .sheet(isPresented: $appModel.showingExportSheet) {
            ActivityView(activityItems: appModel.activityItems)
        }
    }
}

#Preview { ContentView() }
