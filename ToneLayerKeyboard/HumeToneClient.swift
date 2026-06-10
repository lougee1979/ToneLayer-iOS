// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import Foundation
import Combine
import AVFoundation

// Lightweight Hume EVI listener that piggybacks on the keyboard's existing
// dictation audio tap. It streams mic audio to Hume for prosody (vocal tone)
// analysis only — no audio is played back and no chat reply is requested.
@MainActor
final class HumeToneClient: NSObject, ObservableObject {

    @Published var topEmotions: [(name: String, score: Double)] = []
    @Published var isDistressed = false

    private let apiKey = "rlGGHRNACZNW1CU5rsrkdGypMtY57W8Impbm2LW9nhUri1r9"
    private let sendSampleRate: Double = 48_000

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var converter: AVAudioConverter?
    private var convertedFormat: AVAudioFormat?

    private let distressEmotions: Set<String> = [
        "Anxiety", "Distress", "Fear", "Sadness", "Anger", "Tension",
        "Pain", "Horror", "Disappointment", "Shame", "Guilt", "Confusion"
    ]
    private let distressThreshold = 0.35

    var toneSummary: String {
        guard !topEmotions.isEmpty else { return "" }
        return topEmotions
            .prefix(3)
            .map { "\($0.name) \(Int($0.score * 100))%" }
            .joined(separator: ", ")
    }

    func reset() {
        topEmotions = []
        isDistressed = false
    }

    func connect() {
        guard webSocketTask == nil else { return }

        var components = URLComponents(string: "wss://api.hume.ai/v0/evi/chat")!
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: components.url!)
        webSocketTask = task
        task.resume()
        receiveLoop()

        Task {
            let settings: [String: Any] = [
                "type": "session_settings",
                "audio": [
                    "channels": 1,
                    "encoding": "linear16",
                    "sample_rate": Int(sendSampleRate)
                ]
            ]
            try? await sendJSON(settings)
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        converter = nil
        convertedFormat = nil
    }

    // Called from the dictation audio tap with the same buffers fed to SFSpeechRecognizer.
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard webSocketTask != nil else { return }

        if converter == nil {
            guard let target = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sendSampleRate,
                channels: 1,
                interleaved: true
            ) else { return }
            convertedFormat = target
            converter = AVAudioConverter(from: inputFormat, to: target)
        }
        guard let converter, let convertedFormat else { return }

        let ratio = sendSampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: convertedFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        guard let channelData = outBuffer.int16ChannelData else { return }
        let frameCount = Int(outBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Int16>.size)
        let base64 = data.base64EncodedString()

        Task {
            try? await self.sendJSON(["type": "audio_input", "data": base64])
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask?.send(.string(text))
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure:
                    break
                case .success(let message):
                    if case .string(let text) = message {
                        self.handleIncoming(text)
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            type == "user_message"
        else { return }

        guard
            let models = json["models"] as? [String: Any],
            let prosody = models["prosody"] as? [String: Any],
            let scores = prosody["scores"] as? [String: Double]
        else { return }

        topEmotions = scores
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, score: $0.value) }

        if topEmotions.contains(where: { distressEmotions.contains($0.name) && $0.score >= distressThreshold }) {
            isDistressed = true
        }
    }
}
