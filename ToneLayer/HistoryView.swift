// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI

struct HistoryView: View {

    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                logCard
                outcomesSummaryCard
            }
            .padding()
        }
        .appBackground()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rewrite Log", systemImage: "list.clipboard").font(.title3.weight(.semibold))
                Spacer()
                if !appModel.logEntries.isEmpty { Button("Export") { exportLog() }.font(.subheadline) }
            }
            if appModel.logEntries.isEmpty {
                Text("No rewrites yet. Use the Composer to generate your first entry.")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(appModel.logEntries.suffix(5).reversed()) { entry in logRow(entry) }
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

    private var outcomesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Local Outcomes", systemImage: "chart.bar.xaxis").font(.title3.weight(.semibold))
                Spacer()
                Text(appModel.outcomesOptIn ? "On" : "Off").font(.caption.weight(.semibold))
                    .foregroundStyle(appModel.outcomesOptIn ? .green : .secondary)
            }
            if !appModel.outcomesOptIn {
                Text("Turn on Personalization & Outcomes to collect local event summaries.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if appModel.outcomeEvents.isEmpty {
                Text("No local outcome events yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                let rewrites = appModel.outcomeEvents.filter { $0.event == "rewrite_completed" }.count
                let exports  = appModel.outcomeEvents.filter { $0.event.hasPrefix("export_") || $0.event == "copy_result" }.count
                let feedback = appModel.outcomeEvents.filter { $0.event == "feedback_submitted" }.count
                let latest   = appModel.outcomeEvents.suffix(30)
                let avgInput = latest.isEmpty ? 0 : latest.map(\.inputLength).reduce(0,+) / latest.count
                let scores   = appModel.outcomeEvents.compactMap { $0.correctionMetrics?.changeScore }
                let avgCorr  = scores.isEmpty ? 0 : scores.reduce(0,+) / scores.count
                VStack(spacing: 8) {
                    outcomeRow("Tracked events", "\(appModel.outcomeEvents.count)")
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

    private func exportLog() {
        DispatchQueue.global(qos: .background).async {
            let entries = LogStore.shared.load()
            let lines = entries.map { "\($0.timestamp)\t\($0.profile)\t\($0.mode)\t\($0.originalText.replacingOccurrences(of: "\n", with: " "))\t\($0.rewrittenText.replacingOccurrences(of: "\n", with: " "))" }
            let csv = (["Timestamp\tProfile\tMode\tOriginal\tRewritten"] + lines).joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tonelayer_log.tsv")
            try? csv.data(using: .utf8)?.write(to: url)
            DispatchQueue.main.async {
                appModel.activityItems = [url]
                appModel.showingExportSheet = true
            }
        }
    }
}

#Preview {
    HistoryView().environmentObject(AppModel())
}
