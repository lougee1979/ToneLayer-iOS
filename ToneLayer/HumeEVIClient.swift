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

    private let apiKey = "rlGGHRNACZNW1CU5rsrkdGypMtY57W8Impbm2LW9nhUri1r9"

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()

    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []

    private let sendSampleRate: Double = 48_000

    func connect() {
        guard webSocketTask == nil else { return }

        transcript = ""
        assistantText = ""
        topEmotions = []
        audioQueue.removeAll()

        configureAudioSession()

        var components = URLComponents(string: "wss://api.hume.ai/v0/evi/chat")!
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: components.url!)
        webSocketTask = task
        task.resume()

        statusText = "Connecting\u{2026}"
        receiveLoop()

        Task {
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
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        statusText = reason
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            "audio": [
                "channels": 1,
                "encoding": "linear16",
                "sample_rate": Int(sendSampleRate)
            ]
        ]
        try await sendJSON(settings)
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask?.send(.string(text))
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
                case .failure(let error):
                    self.statusText = "Connection closed: \(error.localizedDescription)"
                    self.isConnected = false
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

enum HumeEVIError: LocalizedError {
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .audioFormat: return "Could not configure audio format for Hume EVI"
        }
    }
}
