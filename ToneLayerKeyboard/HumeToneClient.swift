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
final class HumeToneClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    @Published var topEmotions: [(name: String, score: Double)] = []
    @Published var isDistressed = false

    private let apiKey    = "iGJur1J59jimvanwNivAtw1tCyUkEKZA77j9MUSHTApvUwUN"
    private let secretKey = "IMcIJVkuFypeG3x3LQHOy1NmRvZYoRTg1EGVAyodQNCPQ6GGO8HW9TEG0098az2Z"
    private let sendSampleRate: Double = 48_000

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var converter: AVAudioConverter?
    private var convertedFormat: AVAudioFormat?
    private var isConnecting = false

    // Resumed once Hume confirms (or rejects) the websocket handshake, so
    // connect() can fall back to the apiKey auth method if OAuth is rejected.
    // connectTask identifies which attempt the continuation belongs to, so a
    // stale delegate callback from an abandoned attempt can't resume it twice.
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectTask: URLSessionWebSocketTask?

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
        guard webSocketTask == nil, !isConnecting else { return }
        isConnecting = true

        Task {
            defer { isConnecting = false }
            do {
                try await openSocket(useOAuth: true)
            } catch {
                cleanupSocket()
                do {
                    try await openSocket(useOAuth: false)
                } catch {
                    return
                }
            }

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

    /// Opens the EVI websocket using either OAuth (`access_token`) or the
    /// direct `apiKey` query param, waiting for Hume to confirm the
    /// handshake before returning. Throws if Hume rejects the connection,
    /// so connect() can fall back to the other auth method.
    private func openSocket(useOAuth: Bool) async throws {
        var components = URLComponents(string: "wss://api.hume.ai/v0/evi/chat")!
        if useOAuth {
            let token = try await fetchAccessToken()
            components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        } else {
            components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: components.url!)
        webSocketTask = task

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            connectTask = task
            task.resume()
        }
        connectTask = nil

        receiveLoop()
    }

    private func cleanupSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
    }

    private func fetchAccessToken() async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.hume.ai/oauth2-cc/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(apiKey):\(secretKey)".utf8).base64EncodedString()
        req.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else { throw URLError(.userAuthenticationRequired) }
        return token
    }

    func disconnect() {
        cleanupSocket()
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
        guard let webSocketTask else { throw URLError(.notConnectedToInternet) }
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask.send(.string(text))
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

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            guard self.connectTask === webSocketTask, let continuation = self.connectContinuation else { return }
            self.connectContinuation = nil
            self.connectTask = nil
            continuation.resume()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if self.connectTask === task, let continuation = self.connectContinuation {
                self.connectContinuation = nil
                self.connectTask = nil
                continuation.resume(throwing: error ?? URLError(.cannotConnectToHost))
                return
            }
            guard self.webSocketTask === task else { return }
            self.webSocketTask = nil
            self.urlSession = nil
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
