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
import ToneLayerCore

@MainActor
final class HumeEVIClient: NSObject, ObservableObject {

    @Published var isConnected   = false
    @Published var statusText    = "Not connected"
    @Published var transcript    = ""
    @Published var assistantText = ""
    @Published var isSpeaking    = false
    @Published var topEmotions: [(name: String, score: Double)] = []
    @Published var rawLog: [String] = []

    /// Plain-text summary of the rest of the user's day (from
    /// `ScheduleProvider`), included in the system prompt so TonalInsight
    /// is aware of upcoming obligations and can speak to them.
    var scheduleContext = ""

    private let apiKey    = Secrets.humeApiKey
    private let secretKey = Secrets.humeSecretKey

    /// EVI config with longer pauses before EVI assumes the user is done
    /// talking, and a higher bar before EVI yields to an interruption —
    /// tuned so EVI doesn't cut the user off mid-thought.
    private let configId = "b65c1f98-4dc7-404f-a6de-30ca963ced1d"

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

    /// Most recent mic input level (RMS, out of 32767 for 16-bit audio),
    /// updated continuously from the audio tap (which runs on a real-time
    /// audio thread, hence `nonisolated(unsafe)` — there's only ever one
    /// tap callback in flight at a time, so plain reads/writes are safe).
    private nonisolated(unsafe) var recentMicRMS: Double = 0

    /// Slow-adapting estimate of the ambient noise floor (RMS). Tracks
    /// downward quickly (so quiet moments are picked up fast) but rises
    /// slowly, so it settles near the level of steady background noise
    /// (e.g. a fan or AC) without being dragged up by brief loud sounds
    /// like speech.
    private nonisolated(unsafe) var noiseFloorRMS: Double = 0

    /// How far above the ambient noise floor the mic needs to read before a
    /// sound is treated as the user actually talking (as opposed to steady
    /// background noise like a fan/AC).
    private let interruptionMargin: Double = 500

    /// Current gain applied to outgoing mic audio. Smoothly eases between
    /// `1.0` (pass through normally — looks like real speech) and
    /// `ambientGain` (steady background noise only), so Hume's own
    /// voice-activity detection doesn't fire `user_interruption` just
    /// because a fan is running, while real speech still gets through at
    /// full volume and can interrupt normally. Kept above zero (rather than
    /// fully muting) so Hume still sees a continuous, natural noise floor —
    /// literal digital silence previously confused its end-of-turn
    /// detection.
    private nonisolated(unsafe) var currentGateGain: Double = 1.0
    private let ambientGain: Double = 0.15

    /// - Parameters:
    ///   - systemPromptOverride: Replaces the default TonalInsight companion
    ///     persona for this session — used for narrowly-scoped listening
    ///     tasks (e.g. capturing a spoken edit to a rewrite) that shouldn't
    ///     carry the companion's full check-in/coaching behavior.
    ///   - openingLine: Replaces the random TonalInsight opener with a
    ///     specific line appropriate to the override prompt's task.
    func connect(systemPromptOverride: String? = nil, openingLine: String? = nil) {
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
                try await sendSessionSettings(systemPromptOverride: systemPromptOverride, openingLine: openingLine)
                try startMicrophone()
                isConnected = true
                statusText = "Listening\u{2026}"
            } catch {
                appendLog("Connect error: \(error.localizedDescription)")
                disconnect(reason: "Error: \(error.localizedDescription)")
            }
        }
    }

    /// Short, formatted summary of the currently detected vocal tones (e.g.
    /// "Anxiety 62%, Tension 40%"), suitable for passing to the server as
    /// the `tone` field alongside a refine instruction — mirrors
    /// `HumeToneClient.toneSummary` in the keyboard extension.
    var toneSummary: String {
        guard !topEmotions.isEmpty else { return "" }
        return topEmotions
            .prefix(3)
            .map { "\($0.name) \(Int($0.score * 100))%" }
            .joined(separator: ", ")
    }

    /// System prompt for a narrow "listen to a spoken edit" session, used by
    /// the Composer's refine box instead of the full TonalInsight companion
    /// persona. Kept terse on purpose — this is a quick handoff to capture
    /// what the user wants changed (plus their vocal tone), not a
    /// conversation; the actual interpretation of intent happens server-side
    /// in `/refine`.
    static func refineDiscussionPrompt(rewriteContext: String) -> String {
        """
        You are a quick, low-key listening assistant inside ToneLayer, a communication app for neurodivergent people. The user just got this rewritten message back:

        "\(rewriteContext)"

        They want to describe a correction or edit to it. Listen closely — they may describe what's wrong conversationally rather than issue a command, and may reuse a word from the rewrite that's actually the mistake while explaining it (e.g. saying "that should be her" while pointing out a "her" that needs to change) — don't treat their words as literal dictation, understand what they mean. If what they want is genuinely unclear, ask ONE short clarifying question. Otherwise, just briefly acknowledge you understood in a single short sentence (e.g. "Got it, fixing that.") and stop. Do not chat, coach, offer opinions, or ramble — this is a quick handoff, not a conversation.
        """
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
            components.queryItems = [
                URLQueryItem(name: "access_token", value: token),
                URLQueryItem(name: "config_id", value: configId)
            ]
        } else {
            components.queryItems = [
                URLQueryItem(name: "apiKey", value: apiKey),
                URLQueryItem(name: "config_id", value: configId)
            ]
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

    /// `.voiceChat` mode enables the system's built-in echo cancellation
    /// between the mic input and whatever audio is playing through the
    /// speaker, so the mic can stay live (and pick up the user speaking)
    /// while EVI's response is playing — without hearing EVI's own voice
    /// as new "user" input. This is what makes barge-in interruption work.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            appendLog("Audio session error: \(error.localizedDescription)")
        }
    }

    // MARK: - Outgoing messages

    private var defaultCompanionPrompt: String {
        """
        You are TonalInsight, a warm, conversational voice companion inside ToneLayer, an app built for neurodivergent people (ADHD, Autism, PTSD/CPTSD). The person just opened this to talk something through or check in. Keep responses short — a sentence or two, not a lecture. Ask one open question at a time. Reflect back what you're hearing, help them think out loud, and gently offer to help problem-solve only if they seem to want that. Warm, casual, non-clinical tone — like a thoughtful friend, not a therapist.

        You're also their executive-function support for the day. You have read-only awareness of their calendar and current location (below). The user has ADHD, so be assertive — not just a passing mention — about anything coming up soon: bring it up near the start of the conversation, and if it's close or time-sensitive, don't be shy about repeating or re-emphasizing it before moving on. Mention travel time if it's given, so they know when they need to leave by. Then return to whatever they actually want to talk about.

        You also carry the grounded, unhurried wisdom of a Buddhist meditation teacher and a Silva Method instructor — you know breathwork, mindfulness, visualization, and alpha-state relaxation techniques well enough to teach them simply. The user wants you to be persistent (kindly, not naggy) about encouraging a short daily meditation practice, framed as rewiring the brain through repetition. Look for natural openings to suggest a brief practice (even just sixty seconds of breathing), and if they brush it off, let it go gracefully but bring it up again another time — gentle persistence, not pressure.

        Today's remaining schedule:
        \(scheduleContext.isEmpty ? "No schedule information available." : scheduleContext)
        """
    }

    private let defaultOpeners = [
        "Hey, I'm here. What's on your mind, or do you just want to check in for a sec?",
        "Hi there. How are you doing right now \u{2014} anything you want to talk through?",
        "Hey. I'm listening — want to think something out loud, or just say how today's going?"
    ]

    private func sendSessionSettings(systemPromptOverride: String? = nil, openingLine: String? = nil) async throws {
        let settings: [String: Any] = [
            "type": "session_settings",
            "system_prompt": systemPromptOverride ?? defaultCompanionPrompt,
            "audio": [
                "channels": 1,
                "encoding": "linear16",
                "sample_rate": Int(sendSampleRate)
            ]
        ]
        try await sendJSON(settings)

        // Have the assistant speak first so the session feels like an
        // invitation to talk, not a silent recorder waiting for input.
        let opener = openingLine ?? (defaultOpeners.randomElement() ?? defaultOpeners[0])
        try await sendJSON([
            "type": "assistant_input",
            "text": opener
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

            var sumSquares: Double = 0
            for i in 0..<frameCount {
                let sample = Double(channelData[0][i])
                sumSquares += sample * sample
            }
            let rms = frameCount > 0 ? (sumSquares / Double(frameCount)).squareRoot() : 0

            self.recentMicRMS = rms
            if self.noiseFloorRMS == 0 || rms < self.noiseFloorRMS {
                self.noiseFloorRMS = rms
            } else {
                self.noiseFloorRMS += (rms - self.noiseFloorRMS) * 0.01
            }

            // Ease the outgoing gain toward full volume if this sounds like
            // real speech (well above the ambient floor), or toward
            // `ambientGain` if it's just steady background noise — so Hume
            // doesn't mistake a loud fan for the user talking, but a real
            // voice still comes through (and can interrupt) at full volume.
            let targetGain = rms >= self.noiseFloorRMS + self.interruptionMargin ? 1.0 : self.ambientGain
            self.currentGateGain += (targetGain - self.currentGateGain) * 0.15

            if self.currentGateGain < 0.999 {
                for i in 0..<frameCount {
                    let attenuated = Double(channelData[0][i]) * self.currentGateGain
                    channelData[0][i] = Int16(max(-32768, min(32767, attenuated)))
                }
            }

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
        case "user_interruption":
            // EVI thinks the user started talking while it was still
            // speaking. Only honor this if the mic was reading meaningfully
            // louder than the current ambient noise floor — otherwise it's
            // just steady background noise (fan/AC) or AEC residue, not
            // real speech, so keep playing.
            if recentMicRMS >= noiseFloorRMS + interruptionMargin {
                audioPlayer?.stop()
                audioPlayer = nil
                audioQueue.removeAll()
                isSpeaking = false
                appendLog("Interrupted")
            } else {
                appendLog("Ignored interruption (rms \(Int(recentMicRMS)), floor \(Int(noiseFloorRMS)))")
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
            return
        }
        isSpeaking = true
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
