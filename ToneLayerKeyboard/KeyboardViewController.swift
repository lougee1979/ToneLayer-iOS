// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import UIKit
import SwiftUI
import Combine
import Speech
import AVFoundation

// MARK: - Brand colors

extension Color {
    static let brandVioletDark = Color(red: 0.369, green: 0.122, blue: 0.784)
    static let brandViolet     = Color(red: 0.220, green: 0.502, blue: 0.973)
    static let brandGreen      = Color(red: 0.608, green: 0.247, blue: 0.910)
    static let brandWhite      = Color(red: 0.976, green: 0.969, blue: 1.000)
    static let brandGreenMist  = Color(red: 0.882, green: 0.914, blue: 0.996)
    static let brandVioletMist = Color(red: 0.929, green: 0.878, blue: 1.000)
}

// MARK: - Dictation

@MainActor
final class DictationManager: ObservableObject {
    @Published var isRecording = false
    @Published var partialText = ""
    let humeTone = HumeToneClient()

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle(onInsert: @escaping (String) -> Void) {
        if isRecording { finish(onInsert: onInsert) } else { start(onInsert: onInsert) }
    }

    private func start(onInsert: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            Task { @MainActor in self.beginRecording(onInsert: onInsert) }
        }
    }

    private func beginRecording(onInsert: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        humeTone.reset()
        humeTone.connect()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buf, _ in
            self?.request?.append(buf)
            Task { @MainActor in self?.humeTone.sendAudioBuffer(buf, inputFormat: inputFormat) }
        }
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.partialText = result.bestTranscription.formattedString
                if result.isFinal { self.finish(onInsert: onInsert) }
            }
            if error != nil { self.finish(onInsert: onInsert) }
        }
    }

    func finish(onInsert: @escaping (String) -> Void) {
        let text = partialText
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        humeTone.disconnect()
        if !text.isEmpty { onInsert(text); partialText = "" }
    }
}

// MARK: - Keyboard metrics (rotation-safe width)

/// The keyboard's current width, published from the view controller. A
/// background GeometryReader can miss the landscape->portrait shrink (leaving
/// the keys stuck at the larger landscape size); the view controller always
/// gets the layout/rotation callbacks, so it is the authoritative source.
final class KeyboardMetrics: ObservableObject {
    @Published var width: CGFloat = 0
}

// MARK: - Principal class

class KeyboardViewController: UIInputViewController {

    private let metrics = KeyboardMetrics()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(inputVC: self, metrics: metrics))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let top   = host.view.topAnchor.constraint(equalTo: view.topAnchor)
        let bot   = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let lead  = host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trail = host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        [top, bot].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([top, bot, lead, trail])
    }

    // Publish the real view width on every layout pass. This fires after a
    // rotation settles (both directions), so the SwiftUI key sizing always
    // recalculates and never gets stuck at the landscape size.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let w = view.bounds.width
        if w > 0 && abs(metrics.width - w) > 0.5 { metrics.width = w }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }
}

// MARK: - SwiftUI keyboard view

struct KeyboardView: View {
    let inputVC: UIInputViewController
    @ObservedObject var metrics: KeyboardMetrics

    private let serverURL  = "https://tonelayer-server-production.up.railway.app/rewrite"
    private let appToken   = "d731136d97cdd46453e7581465537e0d9aee811512b885c2"
    private let appGroupID = "group.com.alden.tonelayer"
    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    @State private var profileADHD    = false
    @State private var profileAutism  = true
    @State private var profileAUDHD   = false
    @State private var profilePTSD    = false
    @State private var profileCPTSD   = false
    @State private var level             = "Medium"
    @State private var isRewriting       = false
    @State private var status            = ""
    @State private var explanation       = ""
    @State private var showExpl          = true
    @State private var spiralEnabled     = true
    @State private var isShifted         = false
    @State private var isNumbers         = false
    @State private var keyboardTypedText = ""
    @State private var keyboardWidth      = CGFloat(0)
    @State private var previewText        = ""
    @State private var previewGrammar     = ""
    @State private var pendingDeleteCount = 0
    @State private var teachingBody       = ""
    @State private var showTeachingExpanded = false
    @State private var showSpiral          = false
    @State private var spiralNT            = ""
    @State private var spiralGrammar       = ""
    @State private var spiralOriginal      = ""
    @State private var spiralOriginalCount = 0
    @State private var isAnalyzing         = false
    @StateObject private var dictation     = DictationManager()
    @State private var analyzeMode: AnalyzeMode = .narc

    // On-device predictive text + spelling suggestions. Apple's UITextChecker
    // runs entirely on the phone, so nothing you type leaves the device for this.
    @State private var suggestions: [String] = []
    private let spellChecker = UITextChecker()

    private var activeProfileLabel: String {
        var p: [String] = []
        if profileAUDHD {
            p.append("AUDHD")
        } else {
            if profileADHD   { p.append("ADHD") }
            if profileAutism { p.append("Autism") }
        }
        if profilePTSD   { p.append("PTSD") }
        if profileCPTSD  { p.append("CPTSD") }
        return p.isEmpty ? "General ND" : p.joined(separator: "+")
    }

    var body: some View {
        let agreed = defaults?.bool(forKey: "betaAgreementAccepted.v1") ?? false
        return VStack(spacing: 0) {
            topBar
            Divider()
            if !agreed {
                agreementRequiredView
            } else if showTeachingExpanded {
                teachingExpandedView.transition(.move(edge: .top).combined(with: .opacity))
            } else if showSpiral {
                spiralCard.transition(.move(edge: .top).combined(with: .opacity))
            } else if !previewText.isEmpty {
                rewriteResultView.transition(.move(edge: .top).combined(with: .opacity))
            } else {
                mainPanel
            }
        }
        .background(Color(red: 0.945, green: 0.937, blue: 0.984))
        .preferredColorScheme(.light)
        .onAppear { loadSettings(); updateSuggestions() }
        .onChange(of: keyboardTypedText) { _, _ in updateSuggestions() }
        .onReceive(metrics.$width) { w in if w > 0 { keyboardWidth = w } }
    }

    private var agreementRequiredView: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(red: 0.369, green: 0.122, blue: 0.784))
            Text("Open the ToneLayer app to accept the Beta Agreement before using the keyboard.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "yinyang")
                .foregroundStyle(Color.brandVioletDark)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text("ToneLayer").font(.system(size: 11, weight: .bold))
                Text(activeProfileLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 1) {
                Text("ND \u{2192} NT").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandVioletDark).lineLimit(1)
                Text(levelKeyTitle(level)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Button { inputVC.advanceToNextInputMode() } label: {
                    Image(systemName: "globe").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 36, height: 36)
                }
                Button { inputVC.dismissKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private var mainPanel: some View {
        VStack(spacing: 2) {
            teachingStrip
            if !explanation.isEmpty {
                analyzeResult
            }
            if sidePanelWidth < 30 {
                actionBar
            }
            // Status / dictation line — ALWAYS rendered at a fixed height so the
            // keys never shift up or down when a message appears or clears.
            Text(dictation.isRecording && !dictation.partialText.isEmpty
                 ? "🎤 " + dictation.partialText
                 : status)
                .font(.system(size: 10))
                .foregroundStyle(dictation.isRecording ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                .padding(.horizontal, 8)
                .lineLimit(1)
            suggestionBar
            keyboardSection.padding(.horizontal, 4).padding(.bottom, 4)
        }
        .padding(.top, 2)
    }

    // Fixed, stationary strip of up to three on-device suggestions for the word
    // being typed. Stays the same height even when empty so it never jumps.
    private var suggestionBar: some View {
        HStack(spacing: 6) {
            if suggestions.isEmpty {
                Color.clear
            } else {
                ForEach(suggestions, id: \.self) { s in
                    Button { applySuggestion(s) } label: {
                        Text(s)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.systemBackground).opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 6)
    }

    // The run of word characters immediately before the cursor — i.e. the word
    // currently being typed. Always available near the cursor, never truncated.
    private var currentPartialWord: String {
        let before = inputVC.textDocumentProxy.documentContextBeforeInput ?? ""
        let tail = before.reversed().prefix { $0.isLetter || $0 == "'" }
        return String(tail.reversed())
    }

    private func updateSuggestions() {
        let word = currentPartialWord
        guard !word.isEmpty else {
            // Not mid-word: predict the NEXT word so the bar is never empty.
            suggestions = nextWordSuggestions()
            return
        }
        let range = NSRange(location: 0, length: word.utf16.count)
        var results: [String] = []
        // Spelling corrections first, but only if the word is actually misspelled.
        let bad = spellChecker.rangeOfMisspelledWord(in: word, range: range,
                                                     startingAt: 0, wrap: false, language: "en_US")
        if bad.location != NSNotFound,
           let guesses = spellChecker.guesses(forWordRange: range, in: word, language: "en_US") {
            results.append(contentsOf: guesses.prefix(3))
        }
        // Then predictive completions of the partial word.
        if let comps = spellChecker.completions(forPartialWordRange: range, in: word, language: "en_US") {
            results.append(contentsOf: comps.prefix(3))
        }
        var seen = Set<String>(); var top: [String] = []
        for s in results where !seen.contains(s.lowercased()) {
            seen.insert(s.lowercased()); top.append(s)
            if top.count == 3 { break }
        }
        // Never leave the bar empty — fall back to common words so it stays full.
        suggestions = top.isEmpty ? Self.commonWords : top
    }

    /// Predicts likely next words when the user isn't mid-word, so the bar
    /// always has something in it (like Apple's). Uses a small built-in
    /// word-pairs table — entirely on-device, nothing leaves the phone.
    private func nextWordSuggestions() -> [String] {
        let before  = inputVC.textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("!")
            || trimmed.hasSuffix("?") || trimmed.hasSuffix("\n") {
            return Self.sentenceStarters
        }
        let lastWord = String(trimmed.split { $0 == " " || $0 == "\n" }.last ?? "")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:\"'"))
        if let followers = Self.nextWordTable[lastWord], !followers.isEmpty {
            return Array(followers.prefix(3))
        }
        return Self.commonWords
    }

    private func applySuggestion(_ word: String) {
        let proxy = inputVC.textDocumentProxy
        let partial = currentPartialWord
        for _ in 0..<partial.count { proxy.deleteBackward() }
        proxy.insertText(word + " ")
        if keyboardTypedText.hasSuffix(partial) {
            keyboardTypedText.removeLast(partial.count)
        }
        keyboardTypedText += word + " "
        // onChange(keyboardTypedText) will refill the bar with next-word guesses.
    }

    // Words shown at the start of a sentence, and a safe always-available fill.
    static let sentenceStarters = ["I", "The", "Thanks"]
    static let commonWords      = ["the", "to", "and"]

    // Small on-device next-word table: previous word -> likely follow-ups.
    // Crude but private and instant; a learned/on-device-AI model can replace it.
    static let nextWordTable: [String: [String]] = [
        "i": ["am", "have", "think"], "i'm": ["not", "going", "sorry"],
        "you": ["are", "can", "should"], "to": ["the", "be", "do"],
        "the": ["same", "best", "first"], "it": ["is", "was", "would"],
        "is": ["a", "the", "not"], "are": ["you", "not", "going"],
        "have": ["to", "a", "been"], "had": ["to", "a", "been"],
        "thanks": ["for", "so", "again"], "thank": ["you", "you,", "goodness"],
        "can": ["you", "we", "i"], "do": ["you", "not", "it"],
        "we": ["can", "should", "are"], "this": ["is", "was", "week"],
        "that": ["is", "would", "i"], "of": ["the", "course", "my"],
        "for": ["the", "you", "me"], "and": ["i", "the", "then"],
        "a": ["lot", "little", "few"], "my": ["own", "time", "head"],
        "be": ["able", "there", "okay"], "not": ["sure", "going", "really"],
        "going": ["to", "on", "back"], "want": ["to", "you", "a"],
        "need": ["to", "a", "you"], "let": ["me", "you", "us"],
        "me": ["know", "to", "a"], "so": ["much", "i", "that"],
        "sorry": ["for", "i", "about"], "please": ["let", "send", "give"],
        "just": ["wanted", "a", "to"], "wanted": ["to", "you"],
        "feel": ["like", "free", "better"], "good": ["morning", "to", "luck"],
        "how": ["are", "is", "do"], "what": ["is", "do", "i"],
        "when": ["you", "i", "is"], "where": ["are", "is", "you"],
        "with": ["the", "you", "me"], "your": ["time", "help", "message"],
        "about": ["the", "it", "that"], "would": ["be", "you", "like"],
        "could": ["you", "be", "we"], "should": ["be", "i", "we"],
        "will": ["be", "you", "do"], "at": ["the", "all", "least"],
        "in": ["the", "a", "my"], "on": ["the", "my", "it"],
        "hope": ["you", "that", "this"], "hey": ["there", "i", "how"],
        "hi": ["there", "how", "i"], "no": ["problem", "worries", "i"],
        "yes": ["i", "that", "of"], "okay": ["i", "sounds", "thanks"],
    ]

    // Teaching strip — always visible, one line, tap to expand full text
    private var teachingStrip: some View {
        Button {
            if !teachingBody.isEmpty { withAnimation { showTeachingExpanded = true } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.brandVioletDark)
                Text(teachingBody.isEmpty ? "Tap Rewrite to see a teaching note" : teachingBody)
                    .font(.system(size: 10))
                    .foregroundStyle(teachingBody.isEmpty ? Color(UIColor.tertiaryLabel) : Color(red: 0.08, green: 0.10, blue: 0.12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !teachingBody.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.brandVioletDark)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(UIColor.systemBackground).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // Expanded teaching view — replaces main panel, scrollable, full text
    private var teachingExpandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.brandVioletDark)
                    Text("Teaching note")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.brandVioletDark)
                }
                Spacer()
                Button { withAnimation { showTeachingExpanded = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.vertical, showsIndicators: true) {
                Text(teachingBody)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            .frame(maxHeight: 170)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandVioletDark.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // Full-panel rewrite result — replaces the keyboard while a rewrite is
    // ready, showing the explanation alongside the rewrite text and three
    // choices: keep the original, use a grammar-only fix, or use the NT rewrite.
    private var rewriteResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\u{2728}  Here's the rewrite \u{2014} want to use it?")
                .font(.system(size: 13, weight: .bold))
            ScrollView(.vertical, showsIndicators: true) {
                Text(previewText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 140)
            HStack(spacing: 8) {
                chipButton("Original", primary: false) {
                    previewText = ""; previewGrammar = ""; pendingDeleteCount = 0
                    showStatus("Kept your original")
                }
                chipButton("Grammar", primary: false) {
                    applyPreview(previewGrammar.isEmpty ? previewText : previewGrammar)
                }
                chipButton("Use NT \u{2713}", primary: true) { applyPreview(previewText) }
            }
            if !teachingBody.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brandVioletDark.opacity(0.8))
                    Text(teachingBody)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandVioletDark.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var analyzeResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Analysis").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.55, green: 0.20, blue: 0.78))
                Spacer()
                Button { withAnimation { explanation = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.vertical, showsIndicators: true) {
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 88)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.93, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(red: 0.55, green: 0.20, blue: 0.78).opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 6)
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                Button {
                    level = l
                    defaults?.set(l, forKey: "rewriteLevel")
                } label: {
                    Text(levelKeyTitle(l))
                        .font(.system(size: 11, weight: level == l ? .bold : .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(level == l ? Color.brandVioletDark : Color(UIColor.systemGray4))
                        .foregroundStyle(level == l ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 20)
            Button(action: rewrite) {
                HStack(spacing: 3) {
                    if isRewriting { ProgressView().scaleEffect(0.6).tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)) }
                    Text(isRewriting ? "…" : "Rewrite")
                        .font(.system(size: 11, weight: .bold)).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(isRewriting ? Color.brandVioletDark.opacity(0.55) : Color.brandVioletDark)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .disabled(isRewriting || isAnalyzing)
            Button(action: analyzeClipboard) {
                HStack(spacing: 3) {
                    if isAnalyzing { ProgressView().scaleEffect(0.55).tint(.white) }
                    else { Image(systemName: "magnifyingglass").font(.system(size: 11)) }
                    Text(isAnalyzing ? "…" : "Analyze")
                        .font(.system(size: 11, weight: .bold)).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(isAnalyzing ? Color(red: 0.55, green: 0.20, blue: 0.78).opacity(0.55) : Color(red: 0.55, green: 0.20, blue: 0.78))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .disabled(isRewriting || isAnalyzing)
            Button {
                dictation.toggle { text in
                    inputVC.textDocumentProxy.insertText(text)
                    keyboardTypedText += text
                }
            } label: {
                Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.brandViolet)
                    .frame(width: 30, height: 28)
                    .background(dictation.isRecording ? Color.red.opacity(0.12) : Color.brandViolet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Button {
                guard let text = UIPasteboard.general.string, !text.isEmpty else { showStatus("Clipboard is empty"); return }
                keyboardTypedText = text
                inputVC.textDocumentProxy.insertText(text)
                showStatus("Pasted \u{2014} tap Rewrite")
            } label: {
                Image(systemName: "doc.on.clipboard").font(.system(size: 12))
                    .frame(width: 30, height: 28)
                    .background(Color(UIColor.systemGray4))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 6)
    }

    /// Letter keys are square and a fixed Apple-like size. On iPad the spare
    /// width goes to compact side panels (action buttons) plus symmetric margin
    /// so the key block stays centered — exactly like Apple's iPad keyboard.
    private var keySize: CGFloat {
        guard keyboardWidth > 0 else { return 34 }
        let avail = keyboardWidth - sidePanelWidth * 2
        return min((avail - 5 * 9) / 10, 70)
    }

    /// Capped independently of width: on iPad, landscape gives extra
    /// horizontal room but not extra vertical room, so wider keys should
    /// stay rectangular (like Apple's iPad keyboard) rather than growing
    /// the whole keyboard taller and risking clipping.
    private var keyHeight: CGFloat { min(keySize, 56) }
    private var keyAreaWidth: CGFloat { keySize * 10 + 5 * 9 }

    /// Width for the shift/delete keys on the z-row so that row totals
    /// keyAreaWidth exactly (matches the q-row and a-row above it).
    private var letterEdgeKeyWidth: CGFloat { keySize * 1.5 + 2.5 }

    /// Width for the "#+=" / delete keys on the numbers row's bottom row so
    /// that row totals keyAreaWidth exactly.
    private var numberEdgeKeyWidth: CGFloat { keySize * 2.5 + 7.5 }

    /// On iPad the spare width goes to side action panels (like Apple's
    /// modifier columns) so the 10-key block stays square and centered.
    /// 745 ≈ the key block width at the 70pt square cap (70*10 + 5*9).
    private var sidePanelWidth: CGFloat {
        guard keyboardWidth >= 600 else { return 0 }
        return min(max(86, (keyboardWidth - 745) / 2), 280)
    }

    private var keyboardSection: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)
            if sidePanelWidth > 0 {
                leftSidePanel.frame(width: sidePanelWidth)
            }
            centerKeyRows.frame(width: keyboardWidth > 0 ? keyAreaWidth : nil)
            if sidePanelWidth > 0 {
                rightSidePanel.frame(width: sidePanelWidth)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var centerKeyRows: some View {
        VStack(spacing: 6) {
            if isNumbers {
                letterRow(["1","2","3","4","5","6","7","8","9","0"])
                letterRow(["-","/",":",";","(",")","$","&","@","\""])
                HStack(spacing: 5) {
                    modifierKey("#+=", width: numberEdgeKeyWidth) {}
                    letterRow([".",",","?","!","'"])
                    modifierKey(systemImage: "delete.left", width: numberEdgeKeyWidth) {
                        inputVC.textDocumentProxy.deleteBackward()
                        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                    }
                }
            } else {
                letterRow(["q","w","e","r","t","y","u","i","o","p"])
                letterRow(["a","s","d","f","g","h","j","k","l"]).padding(.horizontal, (keySize + 5) / 2)
                HStack(spacing: 5) {
                    modifierKey(systemImage: isShifted ? "shift.fill" : "shift", active: isShifted, width: letterEdgeKeyWidth) { isShifted.toggle() }
                    letterRow(["z","x","c","v","b","n","m"])
                    modifierKey(systemImage: "delete.left", width: letterEdgeKeyWidth) {
                        inputVC.textDocumentProxy.deleteBackward()
                        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                    }
                }
            }
            HStack(spacing: 5) {
                modifierKey(isNumbers ? "ABC" : "123", width: keySize * 1.3) { isNumbers.toggle(); isShifted = false }
                modifierKey(systemImage: "globe", width: keySize * 1.1) { inputVC.advanceToNextInputMode() }
                Button {
                    inputVC.textDocumentProxy.insertText(" ")
                    keyboardTypedText += " "
                } label: {
                    Text("space").font(.system(size: 13, weight: .regular))
                        .frame(maxWidth: .infinity).frame(height: keyHeight)
                        .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(color: Color.black.opacity(0.32), radius: 0, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                modifierKey(".", width: keySize) { inputVC.textDocumentProxy.insertText("."); keyboardTypedText += "." }
                modifierKey(systemImage: "return", width: keySize * 1.6) { inputVC.textDocumentProxy.insertText("\n"); keyboardTypedText += "\n" }
            }
        }
    }

    private var leftSidePanel: some View {
        VStack(spacing: 5) {
            ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                Button {
                    level = l
                    defaults?.set(l, forKey: "rewriteLevel")
                } label: {
                    Text(levelKeyTitle(l))
                        .font(.system(size: 11, weight: level == l ? .bold : .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(level == l ? Color.brandVioletDark : Color(UIColor.systemGray4))
                        .foregroundStyle(level == l ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button(action: rewrite) {
                HStack(spacing: 3) {
                    if isRewriting { ProgressView().scaleEffect(0.6).tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)) }
                    Text(isRewriting ? "…" : "Rewrite")
                        .font(.system(size: 11, weight: .bold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isRewriting ? Color.brandVioletDark.opacity(0.55) : Color.brandVioletDark)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .disabled(isRewriting || isAnalyzing)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 5).padding(.vertical, 1)
    }

    private var rightSidePanel: some View {
        VStack(spacing: 5) {
            Button {
                dictation.toggle { text in
                    inputVC.textDocumentProxy.insertText(text)
                    keyboardTypedText += text
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 13))
                    Text(dictation.isRecording ? "Stop" : "Mic")
                        .font(.system(size: 9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(dictation.isRecording ? Color.red : Color.brandViolet)
                .background(dictation.isRecording ? Color.red.opacity(0.12) : Color.brandViolet.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                guard let text = UIPasteboard.general.string, !text.isEmpty else {
                    showStatus("Clipboard is empty"); return
                }
                keyboardTypedText = text
                inputVC.textDocumentProxy.insertText(text)
                showStatus("Pasted \u{2014} tap Rewrite")
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 13))
                    Text("Paste").font(.system(size: 9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.secondary)
                .background(Color(UIColor.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: analyzeClipboard) {
                VStack(spacing: 2) {
                    if isAnalyzing { ProgressView().scaleEffect(0.5).tint(.white) }
                    else { Image(systemName: "magnifyingglass").font(.system(size: 13)) }
                    Text(isAnalyzing ? "…" : "Analyze")
                        .font(.system(size: 10, weight: .bold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isAnalyzing ? Color(red: 0.55, green: 0.20, blue: 0.78).opacity(0.55) : Color(red: 0.55, green: 0.20, blue: 0.78))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .disabled(isRewriting || isAnalyzing)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 5).padding(.vertical, 1)
    }

    private func letterRow(_ letters: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(letters, id: \.self) { letter in
                letterKey(isShifted && !isNumbers ? letter.uppercased() : letter) {
                    let output = isShifted && !isNumbers ? letter.uppercased() : letter
                    inputVC.textDocumentProxy.insertText(output)
                    keyboardTypedText += output
                    if isShifted { isShifted = false }
                }
            }
        }
    }

    private func letterKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .regular))
                .frame(width: keySize, height: keyHeight)
                .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.32), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(_ title: String, active: Bool = false, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .frame(width: width, height: keyHeight)
                .foregroundStyle(active ? Color.white : Color(red: 0.08, green: 0.10, blue: 0.12))
                .background(active ? Color.brandVioletDark : Color(UIColor.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.22), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(systemImage: String, active: Bool = false, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .semibold))
                .frame(width: width, height: keyHeight)
                .foregroundStyle(active ? Color.white : Color(red: 0.08, green: 0.10, blue: 0.12))
                .background(active ? Color.brandVioletDark : Color(UIColor.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.22), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var spiralCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{1F49A}  Pause for a sec?").font(.system(size: 13, weight: .bold))
            Text("Your text has some patterns that might land differently than you intend.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                chipButton("Keep as-is", primary: false) { spiralOriginal = ""; spiralOriginalCount = 0; withAnimation { showSpiral = false } }
                chipButton("Show me the rewrite", primary: true) { showSpiralPreview() }
            }
            if !teachingBody.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brandVioletDark.opacity(0.8))
                    Text(teachingBody)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandVioletDark.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func chipButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(primary ? Color.brandVioletDark : Color(UIColor.systemGray4))
                .foregroundStyle(primary ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func levelKeyTitle(_ value: String) -> String {
        switch value {
        case "Light":  return "L"
        case "Medium": return "M"
        case "Strong": return "S"
        default:       return value
        }
    }

    private func loadSettings() {
        profileADHD   = defaults?.bool(forKey: "ndprofile.adhd") ?? false
        profileAutism = defaults?.object(forKey: "ndprofile.autism") == nil ? true : (defaults?.bool(forKey: "ndprofile.autism") ?? true)
        profileAUDHD  = defaults?.bool(forKey: "ndprofile.audhd") ?? false
        profilePTSD   = defaults?.bool(forKey: "ndprofile.ptsd") ?? false
        profileCPTSD  = defaults?.bool(forKey: "ndprofile.cptsd") ?? false
        let stored = defaults?.string(forKey: "rewriteLevel") ?? "Medium"
        level = ["Light", "Medium", "Strong"].contains(stored) ? stored : "Medium"
        spiralEnabled = defaults?.object(forKey: "spiralPauseEnabled") == nil ? true : (defaults?.bool(forKey: "spiralPauseEnabled") ?? true)
        showExpl = defaults?.object(forKey: "showExplanation.v2") == nil ? true : (defaults?.bool(forKey: "showExplanation.v2") ?? true)
        teachingBody = defaults?.string(forKey: "lastTeachingNote") ?? ""
    }

    private func rewrite() {
        let proxy = inputVC.textDocumentProxy
        defaults?.synchronize()
        isRewriting = true; explanation = ""; showSpiral = false
        previewText = ""; pendingDeleteCount = 0
        showStatus("Reading your message\u{2026}")
        defaults?.set(true, forKey: "keyboardRewriteInProgress")
        defaults?.synchronize()
        let tone = dictation.humeTone.toneSummary
        let voiceDistressed = dictation.humeTone.isDistressed
        dictation.humeTone.reset()
        Task {
            // Capture the WHOLE message, not just the window iOS exposes near the
            // cursor. If the user typed everything here and the cursor is at the
            // end, our own running copy is complete and we trust it. Otherwise
            // (pasted text, another keyboard, or cursor mid-text) iOS only shows
            // the back end, so we walk the document to read the full text.
            let before = proxy.documentContextBeforeInput ?? ""
            let after  = proxy.documentContextAfterInput ?? ""
            let typed  = keyboardTypedText
            let typedTrim = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            let haveReliableTyped = !typedTrim.isEmpty && after.isEmpty && typed.hasSuffix(before)

            let full: String
            let totalToDelete: Int
            if haveReliableTyped {
                full = typedTrim
                totalToDelete = typed.count
            } else {
                let scanned = await captureFullDocument(proxy)
                full = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                totalToDelete = scanned.count
            }

            guard !full.isEmpty else {
                await MainActor.run {
                    isRewriting = false
                    defaults?.set(false, forKey: "keyboardRewriteInProgress")
                    defaults?.synchronize()
                    showStatus("Type some text first")
                }
                return
            }
            await MainActor.run { showStatus("Sending \(full.count) chars\u{2026}") }
            do {
                let result = try await callServer(text: full, tone: tone)
                var note = result.explanation.isEmpty ? "Rewritten at \(level) for \(activeProfileLabel)." : result.explanation
                if voiceDistressed && !result.isSpiraling {
                    note += " Your voice sounded tense while dictating this, so we paused before sending."
                }
                if spiralEnabled && (result.isSpiraling || voiceDistressed) {
                    await MainActor.run {
                        isRewriting = false
                        spiralNT = result.rewrite; spiralGrammar = result.grammarOnly
                        spiralOriginal = full; spiralOriginalCount = totalToDelete
                        teachingBody = note
                        defaults?.set(note, forKey: "lastTeachingNote")
                        defaults?.set(false, forKey: "keyboardRewriteInProgress")
                        defaults?.synchronize()
                        withAnimation { showSpiral = true }
                    }
                } else {
                    await MainActor.run {
                        isRewriting = false
                        defaults?.set(false, forKey: "keyboardRewriteInProgress")
                        defaults?.synchronize()
                        pendingDeleteCount = totalToDelete
                        teachingBody = note
                        defaults?.set(note, forKey: "lastTeachingNote")
                        previewGrammar = result.grammarOnly
                        withAnimation { previewText = result.rewrite }
                        saveLog(original: full, result: result)
                    }
                }
            } catch {
                await MainActor.run {
                    isRewriting = false
                    defaults?.set(false, forKey: "keyboardRewriteInProgress")
                    defaults?.synchronize()
                    showStatus(error.localizedDescription)
                }
            }
        }
    }

    /// iOS hands a keyboard only the text near the cursor — for a long message
    /// that's just the back end, which is why a rewrite could miss the start.
    /// This reads the WHOLE field: move the cursor to the end, then read backward
    /// window by window until no new text appears. Non-destructive (it only reads
    /// and moves the cursor); the result is shown as a preview before anything is
    /// replaced, so a bad capture can never silently overwrite the message.
    private func captureFullDocument(_ proxy: UITextDocumentProxy) async -> String {
        func readAfter()  async -> String { await MainActor.run { proxy.documentContextAfterInput  ?? "" } }
        func readBefore() async -> String { await MainActor.run { proxy.documentContextBeforeInput ?? "" } }
        func move(_ n: Int) async {
            guard n != 0 else { return }
            await MainActor.run { proxy.adjustTextPosition(byCharacterOffset: n) }
            try? await Task.sleep(nanoseconds: 12_000_000)
        }

        // 1) Move to the very end so every character is "before" the cursor.
        var steps = 0
        var after = await readAfter()
        while !after.isEmpty && steps < 400 {
            await move(after.count)
            after = await readAfter()
            steps += 1
        }
        // 2) Read backward, prepending each new window. Stop when the window
        //    stops changing (some apps cap context and won't scroll) so we can't
        //    loop forever or duplicate text.
        var full = ""
        var lastWindow = ""
        steps = 0
        while steps < 800 {
            let window = await readBefore()
            if window.isEmpty || window == lastWindow { break }
            full = window + full
            lastWindow = window
            await move(-window.count)
            steps += 1
        }
        // 3) Put the cursor back at the end for the delete/replace step.
        steps = 0
        after = await readAfter()
        while !after.isEmpty && steps < 400 {
            await move(after.count)
            after = await readAfter()
            steps += 1
        }
        return full
    }

    private func deleteBackwardChunked(proxy: UITextDocumentProxy, count: Int) async {
        let chunkSize = 50; var remaining = count
        while remaining > 0 {
            let chunk = min(chunkSize, remaining)
            await MainActor.run { for _ in 0..<chunk { proxy.deleteBackward() } }
            remaining -= chunk
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func moveCursorToEnd(proxy: UITextDocumentProxy, knownTextCount: Int) async {
        await MainActor.run { proxy.adjustTextPosition(byCharacterOffset: knownTextCount) }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func insertTextChunked(proxy: UITextDocumentProxy, text: String) async {
        let chunkSize = 400; var index = text.startIndex
        while index < text.endIndex {
            let next  = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<next])
            await MainActor.run { proxy.insertText(chunk) }
            index = next
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Move from the spiral pause into the normal preview, so the user SEES the
    /// rewrite and approves it (Use NT / Grammar / keep Original) instead of the
    /// text being replaced the moment they choose.
    private func showSpiralPreview() {
        previewGrammar     = spiralGrammar
        pendingDeleteCount = spiralOriginalCount
        previewText        = spiralNT
        spiralOriginal = ""; spiralOriginalCount = 0
        withAnimation { showSpiral = false }
    }

    private func applySpiral(_ text: String) {
        let proxy = inputVC.textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let deleteCount = spiralOriginalCount > 0 ? spiralOriginalCount : before.count
        defaults?.set(true, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
        Task {
            await moveCursorToEnd(proxy: proxy, knownTextCount: deleteCount)
            await deleteBackwardChunked(proxy: proxy, count: deleteCount)
            await insertTextChunked(proxy: proxy, text: text)
            await MainActor.run {
                keyboardTypedText = text
                defaults?.set(text, forKey: "testBoxFullText")
                defaults?.set(false, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
                spiralOriginal = ""; spiralOriginalCount = 0
                withAnimation { showSpiral = false }
                showStatus("Applied \u{2713}")
            }
        }
    }

    private func applyPreview(_ text: String) {
        guard !text.isEmpty else { return }
        let proxy = inputVC.textDocumentProxy
        let deleteCount = pendingDeleteCount
        defaults?.set(true, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
        Task {
            await deleteBackwardChunked(proxy: proxy, count: deleteCount)
            await insertTextChunked(proxy: proxy, text: text)
            await MainActor.run {
                keyboardTypedText = text
                defaults?.set(text, forKey: "testBoxFullText")
                defaults?.set(false, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
                previewText = ""; previewGrammar = ""; pendingDeleteCount = 0
                showStatus("Applied \u{2713}")
            }
        }
    }

    private func showStatus(_ msg: String) {
        status = msg
        let readingTime = max(2.5, Double(msg.count) * 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + readingTime) {
            if status == msg { status = "" }
        }
    }

    struct ClaudeResult {
        let rewrite: String
        let explanation: String
        let distortions: [String]
        let grammarOnly: String
        var isSpiraling: Bool { !distortions.isEmpty }
    }

    private func callServer(text: String, tone: String = "") async throws -> ClaudeResult {
        var req = URLRequest(url: URL(string: serverURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken,           forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        var body: [String: Any] = [
            "text":    text,
            "profile": activeProfileLabel,
            "level":   level,
            "mode":    "tonelayer"
        ]
        if !tone.isEmpty { body["tone"] = tone }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NBError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJSON["error"] as? String {
                throw NBError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw NBError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw NBError.badResponse }
        let rewrite: String
        if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
            rewrite = paras.joined(separator: "\n\n")
        } else if let r = parsed["rewrite"] as? String, !r.isEmpty {
            rewrite = r
        } else {
            rewrite = ""
        }
        guard !rewrite.isEmpty else { throw NBError.badResponse }
        return ClaudeResult(
            rewrite:     rewrite,
            explanation: parsed["explanation"] as? String   ?? "",
            distortions: parsed["distortions"] as? [String] ?? [],
            grammarOnly: parsed["grammar_only"] as? String  ?? ""
        )
    }

    private func analyzeClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showStatus("Copy a message first, then tap Analyze")
            return
        }
        isAnalyzing = true
        showStatus("Analyzing \(text.count) chars…")
        Task {
            do {
                let result = try await callNarc(text: text)
                await MainActor.run {
                    isAnalyzing = false
                    withAnimation { explanation = formatNarcResult(result) }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    showStatus(error.localizedDescription)
                }
            }
        }
    }

    private struct NarcPattern {
        let name: String
        let quote: String
        let explanation: String
        let ndImpact: String
    }

    private struct NarcResult {
        let riskLevel: String
        let summary: String
        let patterns: [NarcPattern]
        let validation: String
        let boundaryScript: String
    }

    private func callNarc(text: String) async throws -> NarcResult {
        let narcURL = "https://tonelayer-server-production.up.railway.app/narc"
        var req = URLRequest(url: URL(string: narcURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken,           forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NBError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJSON["error"] as? String {
                throw NBError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw NBError.apiFailed(http.statusCode)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NBError.badResponse
        }
        let summary        = parsed["summary"] as? String ?? ""
        let validation     = parsed["validation"] as? String ?? ""
        let boundaryScript = parsed["boundary_script"] as? String ?? ""
        let riskLevel      = parsed["risk_level"] as? String ?? ""
        let patterns = (parsed["patterns"] as? [[String: Any]] ?? []).map { p in
            NarcPattern(
                name:        p["name"]        as? String ?? "",
                quote:       p["quote"]       as? String ?? "",
                explanation: p["explanation"] as? String ?? "",
                ndImpact:    p["nd_impact"]    as? String ?? ""
            )
        }
        guard !summary.isEmpty || !patterns.isEmpty else { throw NBError.badResponse }
        return NarcResult(riskLevel: riskLevel, summary: summary, patterns: patterns, validation: validation, boundaryScript: boundaryScript)
    }

    /// Turns the structured /narc result into the plain-text block shown in
    /// the Analysis card, leading with the specific patterns found (name +
    /// quote + why it matters) rather than just a generic summary.
    private func formatNarcResult(_ r: NarcResult) -> String {
        var lines: [String] = []
        if !r.summary.isEmpty { lines.append(r.summary) }
        for p in r.patterns {
            var line = "• " + (p.name.isEmpty ? "Pattern noticed" : p.name)
            if !p.quote.isEmpty { line += " — \"\(p.quote)\"" }
            if !p.explanation.isEmpty { line += "\n  \(p.explanation)" }
            if !p.ndImpact.isEmpty { line += "\n  Why this hits harder: \(p.ndImpact)" }
            lines.append(line)
        }
        if !r.validation.isEmpty { lines.append(r.validation) }
        if !r.boundaryScript.isEmpty { lines.append("You could say: \"\(r.boundaryScript)\"") }
        if lines.isEmpty { lines.append("No concerning patterns found in this message.") }
        return lines.joined(separator: "\n\n")
    }

    private func saveLog(original: String, result: ClaudeResult) {
        let entry = RewriteEntry(
            id: UUID(), timestamp: Date(), profile: activeProfileLabel, mode: level,
            originalText: original, rewrittenText: result.rewrite,
            explanation: result.explanation, distortions: result.distortions, spiraling: result.isSpiraling
        )
        DispatchQueue.global(qos: .background).async { LogStore.shared.append(entry) }
    }
}

enum AnalyzeMode { case narc, decode }

enum NBError: LocalizedError {
    case apiFailed(Int); case apiMessage(String); case badResponse
    var errorDescription: String? {
        switch self {
        case .apiFailed(let code): return "Server error (HTTP \(code))"
        case .apiMessage(let s):   return s
        case .badResponse:         return "Unexpected server response"
        }
    }
}

struct RewriteEntry: Codable {
    let id: UUID; let timestamp: Date; let profile: String; let mode: String
    let originalText: String; let rewrittenText: String
    let explanation: String; let distortions: [String]; let spiraling: Bool
}

final class LogStore {
    static let shared = LogStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "rewrite_log.json"
    private var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(fileName)
    }
    func load() -> [RewriteEntry] {
        guard let url = logURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RewriteEntry].self, from: data) else { return [] }
        return entries
    }
    func append(_ entry: RewriteEntry) {
        var entries = load(); entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
    func topPatterns(limit: Int = 40) -> [(pattern: String, count: Int)] {
        let recent = Array(load().suffix(limit))
        let all = recent.flatMap { $0.distortions }.filter { !$0.isEmpty }
        return Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
            .filter { $0.value >= 2 }.sorted { $0.value > $1.value }
            .prefix(3).map { (pattern: $0.key, count: $0.value) }
    }
}
