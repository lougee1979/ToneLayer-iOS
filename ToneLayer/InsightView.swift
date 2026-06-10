//
//  InsightView.swift
//  ToneLayer
//
//  Proof-of-concept screen for the Hume EVI "Insight" feature: listens to
//  the user's voice and surfaces the vocal-tone (prosody) signals Hume
//  detects, without talking back.
//

import SwiftUI

struct InsightView: View {
    @StateObject private var hume = HumeEVIClient()
    @Environment(\.dismiss) private var dismiss
    @State private var liveTyping = false
    var onUseTranscript: ((String) -> Void)? = nil
    var onLiveTranscriptUpdate: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("TonalInsight\u{2122} (Beta)", systemImage: "waveform")
                            .font(.headline)
                            .foregroundStyle(Color.brandVioletDark)
                        Text("Talk for a bit and ToneLayer will listen for what your tone of voice is carrying \u{2014} stress, calm, hesitation, and more. This is an early preview powered by Hume AI; nothing is said back to you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .glassCard(tint: .brandVioletDark)

                    VStack(spacing: 12) {
                        Text(hume.statusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(hume.isConnected ? Color.brandGreen : .secondary)

                        Button {
                            hume.isConnected ? hume.disconnect() : hume.connect()
                        } label: {
                            Label(hume.isConnected ? "Stop Listening" : "Start Listening",
                                  systemImage: hume.isConnected ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(hume.isConnected ? .red : .brandGreen)

                        if onLiveTranscriptUpdate != nil {
                            Toggle(isOn: $liveTyping) {
                                Label("Type what I say", systemImage: "keyboard")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .tint(.brandGreen)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .glassCard(tint: .brandGreen)

                    if !hume.topEmotions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("What your voice is carrying", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(Color.brandVioletDark)
                            ForEach(hume.topEmotions, id: \.name) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline)
                                    Spacer()
                                    ProgressView(value: item.score)
                                        .frame(width: 120)
                                    Text(String(format: "%.0f%%", item.score * 100))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .glassCard(tint: .brandViolet, cornerRadius: 18)
                    }

                    if !hume.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Last heard", systemImage: "text.quote")
                                .font(.headline)
                                .foregroundStyle(Color.brandVioletDark)
                            Text(hume.transcript)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let onUseTranscript {
                                Button {
                                    let text = hume.transcript
                                    hume.disconnect()
                                    onUseTranscript(text)
                                    dismiss()
                                } label: {
                                    Label("Use this in ToneLayer", systemImage: "arrow.turn.left.up")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.brandGreen)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .glassCard(tint: .brandViolet, cornerRadius: 18)
                    }

                    if !hume.assistantText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(hume.isSpeaking ? "Speaking\u{2026}" : "ToneLayer responded", systemImage: "waveform.circle")
                                .font(.headline)
                                .foregroundStyle(Color.brandGreen)
                            Text(hume.assistantText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .glassCard(tint: .brandGreen, cornerRadius: 18)
                    }

                    if !hume.rawLog.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Debug log", systemImage: "ladybug")
                                .font(.headline)
                                .foregroundStyle(Color.brandVioletDark)
                            ForEach(Array(hume.rawLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .glassCard(tint: .brandViolet, cornerRadius: 18)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.945, green: 0.937, blue: 0.984))
            .navigationTitle("TonalInsight\u{2122}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        hume.disconnect()
                        dismiss()
                    }
                }
            }
            .onChange(of: hume.transcript) { _, newValue in
                if liveTyping {
                    onLiveTranscriptUpdate?(newValue)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
