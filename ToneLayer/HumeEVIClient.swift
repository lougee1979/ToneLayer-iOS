//
//  HumeEVIClient.swift
//  ToneLayer
//
//  Minimal client for Hume's Empathic Voice Interface (EVI).
//  Streams microphone audio to EVI over a websocket and surfaces the
//  prosody (vocal tone) scores Hume returns for each spoken utterance.
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class HumeEVIClient: NSObject, ObservableObject {

    @Published var isConnected   = false
    @Published var statusText    = "Not connected"
    @Published var transcript    = ""
    @Published var assistantText = ""
    @Published var isSpeaking    = false
    @Published var topEmotions: [(name: String, score: Double)] = []
    @Published var rawLog: [String] = []

    private let apiKey    = "iGJur1J59jimvanwNivAtw1tCyUkEKZA77j9MUSHTApvUwUN"
    private let secretKey = "IMcIJVkuFypeG3x3LQHOy1NmRvZYoRTg1EGVAyodQNCPQ6GGO8HW9TEG0098az2Z"

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()

    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    private var isConnecting = false

    // Resumed once Hume confirms (or rejects) the websocket handshake, so
    // `connect()` knows definitively whether this attempt worked instead of
    // guessing from a later `receive()` failure. `connectTask` identifies
    // which attempt the continuation belongs to, so a stale delegate
    // callback from an earlier (already-abandoned) attempt can't resume it
    // a second time and crash.
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectTask: URLSessionWebSocketTask?

    private let sendSampleRate: Double = 48_000

    func connect() {
        guard webSocketTask == nil, !isConnecting else { return }
        isConnecting = true

        transcript = ""
        assistantText = ""
        topEmotions = []
        audioQueue.removeAll()

        configureAudioSession()
        statusText = "Connecting\u{2026}"

        Task {
            defer { isConnecting = false }
            do {
                try await openSocket(useOAuth: true)
            } catch {
                appendLog("OAuth connect failed (\(error.localizedDescription)) \u{2014} retrying with API key")
                cleanupSocket()
                do {
                    try await openSocket(useOAuth: false)
                } catch {
                    appendLog("Connect error: \(error.localizedDescription)")
                    disconnect(reason: "Error: \(error.localizedDescription)")
                    return
                }
            }

            do {
                try await sendSessionSettings()
                try startMicrophone()
                isConnected = true
                statusText = "Listening\u{2026}"
            } catch {
                appendLog("Connect error: \(error.localizedDescription)")
                disconnect(reason: "Error: \(error.localizedDescription)")
            }
        }
    }

    func disconnect(reason: String = "Not connected") {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioPlayer?.stop()
        audioPlayer = nil
        audioQueue.removeAll()
        isSpeaking = false
        cleanupSocket()
        isConnected = false
        statusText = reason
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Connection

    /// Opens the EVI websocket using either OAuth (`access_token`) or the
    /// direct `apiKey` query param, and waits for Hume to confirm the
    /// handshake before returning. Throws if Hume rejects the connection
    /// (e.g. a 401 during the websocket upgrade), so `connect()` can fall
    /// back to the other auth method instead of surfacing a vague
    /// "socket is not connected" error.
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

    // MARK: - Auth

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
        else { throw HumeEVIError.tokenFailed }
        return token
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            appendLog("Audio session error: \(error.localizedDescription)")
        }
    }

    // MARK: - Outgoing messages

    private func sendSessionSettings() async throws {
        let settings: [String: Any] = [
            "type": "session_settings",
            "system_prompt": """
            You are TonalInsight, a warm, conversational voice companion inside ToneLayer, an app built for neurodivergent people (ADHD, Autism, PTSD/CPTSD). The person just opened this to talk something through or check in. Keep responses short — a sentence or two, not a lecture. Ask one open question at a time. Reflect back what you're hearing, help them think out loud, and gently offer to help problem-solve only if they seem to want that. Warm, casual, non-clinical tone — like a thoughtful friend, not a therapist.
            """,
            "audio": [
                "channels": 1,
                "encoding": "linear16",
                "sample_rate": Int(sendSampleRate)
            ]
        ]
        try await sendJSON(settings)

        // Have the assistant speak first so the session feels like an
        // invitation to talk, not a silent recorder waiting for input.
        let openers = [
            "Hey, I'm here. What's on your mind, or do you just want to check in for a sec?",
            "Hi there. How are you doing right now \u{2014} anything you want to talk through?",
            "Hey. I'm listening — want to think something out loud, or just say how today's going?"
        ]
        try await sendJSON([
            "type": "assistant_input",
            "text": openers.randomElement() ?? openers[0]
        ])
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let webSocketTask else { throw HumeEVIError.connectionFailed }
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask.send(.string(text))
    }

    // MARK: - Microphone capture

    private func startMicrophone() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sendSampleRate,
            channels: 1,
            interleaved: true
        ) else { throw HumeEVIError.audioFormat }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw HumeEVIError.audioFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = self.sendSampleRate / inputFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

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

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Incoming messages

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure:
                    // The websocket delegate's didCompleteWithError handles
                    // status updates and cleanup for unexpected closes.
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
            let type = json["type"] as? String
        else { return }

        switch type {
        case "user_message":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                transcript = transcript.isEmpty ? content : transcript + " " + content
            }
            if let models = json["models"] as? [String: Any],
               let prosody = models["prosody"] as? [String: Any],
               let scores = prosody["scores"] as? [String: Double] {
                topEmotions = scores
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { (name: $0.key, score: $0.value) }
            }
            appendLog("You said: \(transcript)")
        case "assistant_message":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                assistantText = content
                appendLog("EVI: \(content)")
            }
        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            statusText = "Error: \(message)"
            appendLog("Error: \(message)")
        case "audio_output":
            if let base64 = json["data"] as? String,
               let audioData = Data(base64Encoded: base64) {
                enqueueAudio(audioData)
            }
        default:
            break
        }
    }

    private func appendLog(_ line: String) {
        rawLog.append(line)
        if rawLog.count > 50 { rawLog.removeFirst(rawLog.count - 50) }
    }

    // MARK: - Playback of EVI's spoken response

    private func enqueueAudio(_ data: Data) {
        audioQueue.append(data)
        if audioPlayer == nil || audioPlayer?.isPlaying == false {
            playNextAudio()
        }
    }

    private func playNextAudio() {
        guard !audioQueue.isEmpty else {
            isSpeaking = false
            resumeMicrophone()
            return
        }
        if !isSpeaking {
            isSpeaking = true
            pauseMicrophone()
        }
        let data = audioQueue.removeFirst()
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            player.play()
        } catch {
            appendLog("Playback error: \(error.localizedDescription)")
            playNextAudio()
        }
    }

    // MARK: - Turn-taking

    private func pauseMicrophone() {
        guard audioEngine.isRunning else { return }
        audioEngine.pause()
    }

    private func resumeMicrophone() {
        guard isConnected, !audioEngine.isRunning else { return }
        try? audioEngine.start()
    }
}

extension HumeEVIClient: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playNextAudio()
        }
    }
}

extension HumeEVIClient: URLSessionWebSocketDelegate {
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
                // Handshake never succeeded — let connect() try the fallback auth method.
                self.connectContinuation = nil
                self.connectTask = nil
                continuation.resume(throwing: error ?? HumeEVIError.connectionFailed)
                return
            }
            // Connection dropped after being established (or a stale callback
            // from an already-abandoned attempt) — only act if this is still
            // the active socket.
            guard self.webSocketTask === task else { return }
            self.webSocketTask = nil
            self.urlSession = nil
            // If Hume already sent an explicit "error" message (e.g. zero
            // credits), keep that message instead of overwriting it with a
            // generic "Connection closed".
            if !self.statusText.hasPrefix("Error:") {
                let description = error?.localizedDescription ?? "Connection closed"
                self.statusText = "Connection closed: \(description)"
            }
            self.isConnected = false
        }
    }
}

enum HumeEVIError: LocalizedError {
    case audioFormat
    case tokenFailed
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .audioFormat: return "Could not configure audio format for Hume EVI"
        case .tokenFailed: return "Could not authenticate with Hume"
        case .connectionFailed: return "Could not connect to Hume EVI"
        }
    }
}
