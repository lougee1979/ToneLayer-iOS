// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import UIKit
import SwiftUI
import Combine
import Speech
import AVFoundation
import ToneLayerCore

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
    @Published var lastToneSummary = ""
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
        lastToneSummary = humeTone.topEmotionLabel
        humeTone.disconnect()
        if !text.isEmpty { onInsert(text); partialText = "" }
    }
}

// MARK: - Native key styling

/// The subtle bottom-edge "keycap" shadow every native iOS keyboard key
/// has, which this custom keyboard was missing entirely (flat, shadowless
/// keys read as obviously custom-drawn rather than a real keyboard).
extension View {
    func keycapShadow() -> some View {
        shadow(color: Color.black.opacity(0.30), radius: 0, x: 0, y: 1)
    }

    /// Extends a key's invisible tap target out to the midpoint of the
    /// gaps around it, so a tap landing in the space *between* two keys
    /// still registers on the nearer one — matching Apple's own keyboard,
    /// which has no dead space anywhere in the key area. Without this, a
    /// tap that lands a few points off-center (routine at normal typing
    /// speed) falls into the gap between keys and silently drops, which
    /// is what reads as "the keyboard missed my letter."
    func keyTapTarget(h: CGFloat = 2.5, v: CGFloat = 3) -> some View {
        self
            .padding(.horizontal, h)
            .padding(.vertical, v)
            .contentShape(Rectangle())
            .padding(.horizontal, -h)
            .padding(.vertical, -v)
    }
}

/// Scales a button's label up on press. Used for ToneLayer's own tiny
/// controls (L/M/S tiles, action icons, close button) — those shrank down
/// to small tap targets, so unlike the full-size letter keys, they need
/// clear press feedback to confirm which one actually got hit.
struct ExpandOnPressStyle: ButtonStyle {
    var scale: CGFloat = 1.35
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// The pointed "speech bubble" shape native iOS uses for the enlarged
/// key-press preview popup — a rounded rectangle with a small triangular
/// tail pointing down at the key being pressed, instead of a plain
/// rounded rectangle floating above it.
struct KeyPopupBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 8
        let tailWidth: CGFloat = 16
        let tailHeight: CGFloat = 7
        let bodyRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)

        var path = Path(roundedRect: bodyRect, cornerRadius: cornerRadius, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: rect.midX - tailWidth / 2, y: bodyRect.maxY))
        tail.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        tail.addLine(to: CGPoint(x: rect.midX + tailWidth / 2, y: bodyRect.maxY))
        tail.closeSubpath()
        path.addPath(tail)
        return path
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

class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {

    private var heightConstraint: NSLayoutConstraint?
    private var isContentExpanded = false

    /// Fires whenever the document's text changes for any reason — typed on
    /// this keyboard, pasted, autocorrected, or edited by the host app.
    /// `KeyboardView` uses this to catch text that arrived some way other
    /// than its own keys (e.g. the system paste bubble), which its own
    /// tracked buffer never sees.
    var onTextDidChange: (() -> Void)?

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        onTextDidChange?()
    }

    /// Third-party keyboards must opt in to the standard system key-click
    /// sound; Apple's own keyboard has it on by default.
    var enableInputClicksWhenVisible: Bool { true }

    /// Portrait needs room for the teaching strip, action bar, suggestion
    /// bar, and 4 rows of keys without clipping. Landscape has far less
    /// screen height to work with, so the SwiftUI content also shrinks
    /// (smaller keys, hidden teaching strip) to match a smaller request —
    /// otherwise the keyboard ends up consuming nearly the whole screen.
    private func requestedHeight(isLandscape: Bool) -> CGFloat {
        let base: CGFloat
        // 5 rows of real-Apple-sized (~70pt, square) keys is ~373pt alone
        // (see `keySize`), plus one merged toolbar row above them (branding,
        // level, action icons, suggestions/status all in one row now — see
        // `toolbarRow`; portrait adds the teaching strip, landscape hides
        // it) — computed and verified against the actual key/row math, not
        // guessed. Lowered from the pre-merge budget (was 510/535, 250/350)
        // by exactly what merging the old topBar+actionBar+status+
        // suggestion rows into one freed up, so that freed height doesn't
        // sit unused below the keys — it comes back out of the total
        // request instead, keeping the keys the same real size without
        // asking the system for any more room than before.
        if UIDevice.current.userInterfaceIdiom == .pad { base = isLandscape ? 427 : 452 }
        else { base = isLandscape ? 188 : 288 }
        // The rewrite-result screen keeps the on-screen keys visible
        // (needed to type into the "Refine" field, which — being a text
        // field inside a keyboard extension — can never summon a system
        // keyboard of its own) on top of the rewrite text, its
        // explanation, and three choice buttons. That's more content than
        // the base height budget allows, so it gets extra room while that
        // screen is showing.
        return isContentExpanded ? base + 120 : base
    }

    /// Called by `KeyboardView` whenever the rewrite-result screen (with
    /// its rewrite text + explanation + keyboard all on one screen) opens
    /// or closes, so the keyboard's own height can grow to fit it instead
    /// of squeezing the rewrite text down to nothing.
    func setContentExpanded(_ expanded: Bool) {
        guard isContentExpanded != expanded else { return }
        isContentExpanded = expanded
        let isLandscape = view.bounds.width > view.bounds.height
        heightConstraint?.constant = requestedHeight(isLandscape: isLandscape)
    }

    private let metrics = KeyboardMetrics()

    override func viewDidLoad() {
        super.viewDidLoad()
        // KeyboardView forces `.preferredColorScheme(.light)`, but that only
        // affects SwiftUI-native colors — raw UIColor-based colors (e.g.
        // .systemGray4, .tertiaryLabel) still follow the real system Dark
        // Mode setting unless the UIKit trait itself is overridden here too,
        // which is what made dark mode unreadable (light-mode text on a
        // dark-styled label sitting on the forced-light background).
        overrideUserInterfaceStyle = .light

        let isLandscape = view.bounds.width > view.bounds.height
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: requestedHeight(isLandscape: isLandscape))
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint

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

    // Custom keyboards don't always re-layout their SwiftUI content when the
    // device rotates, leaving the old (portrait) key sizing on screen. Force
    // a layout pass so the GeometryReader-driven sizing recalculates, and
    // update the requested height to match the new orientation.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let isLandscape = size.width > size.height
        heightConstraint?.constant = requestedHeight(isLandscape: isLandscape)
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }
}

// MARK: - SwiftUI keyboard view

struct KeyboardView: View {
    let inputVC: KeyboardViewController
    @ObservedObject var metrics: KeyboardMetrics

    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupID) }
    private let router = RewriteRouter()
    private let refineClient = RefineClient()
    private let redactor = PIIRedactor()

    @State private var profileADHD    = false
    @State private var profileAutism  = true
    @State private var profileAUDHD   = false
    @State private var profilePTSD    = false
    @State private var profileCPTSD   = false
    @State private var profileDyslexic = false
    @State private var pressedKeyTitle: String? = nil
    @State private var level             = "Medium"
    @State private var isRewriting       = false
    @State private var status            = ""
    @State private var explanation       = ""
    @State private var showExpl          = true
    @State private var spiralEnabled     = true
    @State private var isShifted         = false
    @State private var isNumbers         = false
    @State private var isSymbols         = false
    @State private var capsLocked        = false
    @State private var lastShiftTap: Date? = nil
    @State private var deleteTimer: Timer? = nil
    @State private var spaceDragAccumulated: CGFloat = 0
    @State private var keyboardTypedText = ""
    @State private var keyboardWidth      = CGFloat(0)
    @State private var keyboardHeight     = CGFloat(0)
    @State private var previewText        = ""
    @State private var previewGrammar     = ""
    @State private var previewSource: RewriteSource = .cloud
    @State private var pendingDeleteCount = 0
    @State private var refineInstruction  = ""
    @State private var refineTone         = ""
    @State private var isRefining         = false
    @State private var teachingBody       = ""
    @State private var showTeachingExpanded = false
    @State private var showSpiral          = false
    @State private var spiralNT            = ""
    @State private var spiralGrammar       = ""
    @State private var spiralOriginal      = ""
    @State private var spiralOriginalCount = 0
    @State private var isAnalyzing         = false
    // On-device predictive text + spelling suggestions. Apple's UITextChecker
    // runs entirely on the phone, so nothing you type leaves the device for this.
    @State private var suggestions: [String] = []
    @State private var personalWordModel = PersonalizedWordModel()
    @StateObject private var dictation     = DictationManager()
    private let textChecker = UITextChecker()
    private let spellChecker = UITextChecker()
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let autocorrectTriggers: Set<String> = [" ", "\n", ".", ",", "!", "?", ";", ":"]

    /// `UITextChecker.learnWord` teaches the device's shared system
    /// dictionary — persists across launches once learned, so repeat calls
    /// are harmless. Without this, "adhd"/"audhd"/"cptsd" aren't real
    /// dictionary words, so autocorrect silently "fixes" them to the
    /// nearest real word (e.g. "adhd" -> "add") — actively wrong for an
    /// app whose whole purpose is talking about ND conditions. Learning
    /// both casings since UITextChecker's own case-matching isn't
    /// guaranteed to generalize from just one.
    private static func teachNDTerms() {
        for word in ["adhd", "ADHD", "audhd", "AuDHD", "cptsd", "CPTSD", "ptsd", "PTSD"] {
            UITextChecker.learnWord(word)
        }
    }
    private let accentVariants: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å"],
        "e": ["è", "é", "ê", "ë"],
        "i": ["ì", "í", "î", "ï"],
        "o": ["ò", "ó", "ô", "ö", "õ", "ø"],
        "u": ["ù", "ú", "û", "ü"],
        "n": ["ñ"],
        "c": ["ç"],
        "s": ["ß"],
        "y": ["ÿ"]
    ]

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
        if profileDyslexic { p.append("Dyslexic") }
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
        .background(.ultraThinMaterial)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { keyboardHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newHeight in keyboardHeight = newHeight }
            }
        )
        .preferredColorScheme(.light)
        .onAppear {
            Self.teachNDTerms()
            loadSettings(); seedTypedTextFromProxy(); updateAutoCapitalization(); updateSuggestions()
            // Deferred to the next runloop turn so it runs after this
            // keystroke's own `keyboardTypedText += s` has already executed
            // (textDidChange can fire synchronously mid-insertText/
            // deleteBackward) — otherwise the very first keystroke's
            // buffer-still-empty moment gets misread as "external text
            // arrived" and reseeded from a proxy context that's just that
            // one character, corrupting the buffer for the whole session.
            inputVC.onTextDidChange = { DispatchQueue.main.async { seedTypedTextFromProxy() } }
            hapticGenerator.prepare()
        }
        .onChange(of: keyboardTypedText) { _, _ in updateSuggestions() }
        .onReceive(metrics.$width) { w in if w > 0 { keyboardWidth = w } }
        .onChange(of: dictation.lastToneSummary) { _, newValue in
            if !newValue.isEmpty { showStatus("Sounded: " + newValue) }
        }
        .onChange(of: previewText) { _, newValue in
            inputVC.setContentExpanded(!newValue.isEmpty)
        }
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

    // Shrunk to the bare minimum — a tiny brand mark and the close button,
    // no text labels. Every byte of height here is height the actual keys
    // don't get, so this row is deliberately as small as a tappable target
    // can reasonably be, matching the "ToneLayer's own controls are the
    // tiny elements, not a full row" direction.
    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "yinyang")
                .foregroundStyle(Color.brandVioletDark)
                .font(.system(size: 10))
            Spacer()
            Button { inputVC.dismissKeyboard() } label: {
                Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18, height: 16)
            }
            .buttonStyle(ExpandOnPressStyle())
            .accessibilityLabel("Close keyboard")
            .accessibilityHint("Hides the keyboard and returns to the app.")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
    }

    private var mainPanel: some View {
        VStack(spacing: 2) {
            if !isLandscape {
                teachingStrip
            }
            if !explanation.isEmpty {
                analyzeResult
            }
            toolbarRow
            keyboardSection.padding(.horizontal, 4).padding(.bottom, 4)
        }
        .padding(.top, 2)
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
        // Spelling corrections first, but only if the word is actually
        // misspelled — and never for the never-autocorrect ND terms (see
        // `autocorrectLastWord`), so "adhd" doesn't show "add" as a
        // tappable suggestion even before autocorrect-on-space would fire.
        let bad = spellChecker.rangeOfMisspelledWord(in: word, range: range,
                                                     startingAt: 0, wrap: false, language: "en_US")
        if bad.location != NSNotFound, !Self.neverAutocorrect.contains(word.lowercased()),
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
        suggestions = (top.isEmpty ? Self.commonWords : top).map { matchCapitalization(of: word, to: $0) }
    }

    /// Predicts likely next words when the user isn't mid-word, so the bar
    /// always has something in it (like Apple's). Prefers `personalWordModel`
    /// (built from the user's own past rewrites) over the small built-in
    /// word-pairs table below — entirely on-device either way, nothing
    /// leaves the phone.
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
        // Personalized (built from this user's own past rewrites) first;
        // fall back to the generic static table, then the safe defaults —
        // so suggestions only ever get better as history accumulates,
        // never regress to "no suggestions" for a new user.
        let personal = personalWordModel.followers(of: lastWord, limit: 3)
        if !personal.isEmpty { return personal }
        if let followers = Self.nextWordTable[lastWord], !followers.isEmpty {
            return Array(followers.prefix(3))
        }
        return Self.commonWords
    }

    // Words shown at the start of a sentence, and a safe always-available fill.
    static let sentenceStarters = ["I", "The", "Thanks"]
    static let commonWords      = ["the", "to", "and"]

    // Small on-device next-word table: previous word -> likely follow-ups.
    // Fallback for words `personalWordModel` hasn't seen yet (new users, or
    // a word not yet in this person's own rewrite history).
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
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .accessibilityLabel(teachingBody.isEmpty ? "Teaching note" : "Teaching note: \(teachingBody)")
        .accessibilityHint(teachingBody.isEmpty ? "Nothing to show yet. Tap Rewrite first." : "Opens the full explanation.")
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
                .accessibilityLabel("Close teaching note")
                .accessibilityHint("Returns to the keyboard.")
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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\u{2728}  Here's the rewrite \u{2014} want to use it?")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(previewSource == .onDevice ? "On-device" : "Precise \u{2014} via Claude")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(previewText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
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
                refineRow
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.91, green: 0.98, blue: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandVioletDark.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 12).padding(.vertical, 8)
            // A custom keyboard can't summon a system keyboard for the refine
            // field above (no such thing as a keyboard for a keyboard), so
            // this view keeps its own on-screen keys visible here and typing
            // routes into refineInstruction instead of the host app's text
            // field — see the `!previewText.isEmpty` branch in
            // insertCharacter/deleteBackward.
            keyboardSection.padding(.horizontal, 4).padding(.bottom, 4)
        }
    }

    /// Not quite right? tell it what to fix — always shown alongside a
    /// rewrite result, on-device or cloud. A correction always goes to the
    /// AI, never handled locally by pattern-matching.
    private var refineRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                if refineInstruction.isEmpty {
                    Text("Not quite right? Tell it what to fix\u{2026}")
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                } else {
                    Text(refineInstruction)
                        .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                }
                Spacer(minLength: 0)
            }
                .font(.system(size: 12))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button {
                dictation.toggle { text in
                    refineInstruction += text
                    refineTone = dictation.humeTone.toneSummary
                }
            } label: {
                Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.brandViolet)
                    .frame(width: 26, height: 26)
                    .background((dictation.isRecording ? Color.red : Color.brandViolet).opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .accessibilityLabel(dictation.isRecording ? "Stop recording" : "Speak your correction")
            .accessibilityHint("Lets you say what to fix instead of typing it — your tone while speaking helps the correction land right.")
            Button {
                refine()
            } label: {
                Group {
                    if isRefining { ProgressView().scaleEffect(0.55).tint(.white) }
                    else { Text("Refine").font(.system(size: 11, weight: .semibold)) }
                }
                .frame(width: 52, height: 26)
                .background(Color.brandVioletDark)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .disabled(isRefining || refineInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func refine() {
        let instruction = refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !previewText.isEmpty else { return }
        isRefining = true
        let tone = refineTone
        Task {
            do {
                let result = try await refineClient.refine(
                    previousRewrite: previewText,
                    instruction: instruction,
                    profile: activeProfileLabel,
                    level: level,
                    mode: "tonelayer",
                    tone: tone
                )
                await MainActor.run {
                    isRefining = false
                    refineInstruction = ""
                    refineTone = ""
                    previewGrammar = result.grammarOnly
                    previewSource = result.source
                    if !result.explanation.isEmpty {
                        teachingBody = result.explanation
                        defaults?.set(result.explanation, forKey: "lastTeachingNote")
                    }
                    withAnimation { previewText = result.rewrite }
                }
            } catch {
                await MainActor.run {
                    isRefining = false
                    showStatus(error.localizedDescription)
                }
            }
        }
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
                .accessibilityLabel("Close analysis")
                .accessibilityHint("Dismisses this analysis result.")
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

    /// Everything that used to be three separate rows — the level toggle
    /// (previously duplicated in `topBar` as "ND → NT"), the action icons,
    /// the status line, and the predictive-suggestion strip — merged into
    /// one row. Every row folded in here is a full row's height handed back
    /// to the actual keys, without changing the keyboard's total requested
    /// height (see `requestedHeight`, which was sized down to match).
    /// Trailing region shows suggestions while typing, or the status
    /// message in the same space when there is one — never both at once,
    /// so nothing needs its own dedicated row just for that.
    private var toolbarRow: some View {
        HStack(spacing: 3) {
            ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                Button {
                    level = l
                    defaults?.set(l, forKey: "rewriteLevel")
                } label: {
                    Text(String(levelKeyTitle(l).prefix(1)))
                        .font(.system(size: 10, weight: level == l ? .bold : .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(level == l ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                        .background(level == l ? Color.brandVioletDark : Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(ExpandOnPressStyle())
                .accessibilityLabel("\(l) rewrite strength")
                .accessibilityHint(level == l ? "Currently selected." : "Sets how strongly your text gets rewritten.")
            }
            Divider().frame(height: 14)
            Button(action: rewrite) {
                Group {
                    if isRewriting { ProgressView().scaleEffect(0.45).tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)) }
                }
                .frame(width: 20, height: 18)
                .foregroundStyle(.white)
                .background(Color.brandVioletDark.opacity(isRewriting ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(ExpandOnPressStyle())
            .disabled(isRewriting || isAnalyzing)
            .accessibilityLabel(isRewriting ? "Rewriting" : "Rewrite")
            .accessibilityHint("Rewrites your text to sound more neurotypical.")
            Button(action: analyzeClipboard) {
                Group {
                    if isAnalyzing { ProgressView().scaleEffect(0.4).tint(.white) }
                    else { Image(systemName: "magnifyingglass").font(.system(size: 10)) }
                }
                .frame(width: 20, height: 18)
                .foregroundStyle(.white)
                .background(Color(red: 0.55, green: 0.20, blue: 0.78).opacity(isAnalyzing ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(ExpandOnPressStyle())
            .disabled(isRewriting || isAnalyzing)
            .accessibilityLabel(isAnalyzing ? "Analyzing" : "Analyze")
            .accessibilityHint("Checks your clipboard text for manipulative or narcissistic patterns.")
            Button {
                dictation.toggle { text in
                    inputVC.textDocumentProxy.insertText(text)
                    keyboardTypedText += text
                }
            } label: {
                Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.brandViolet)
                    .frame(width: 20, height: 18)
                    .background((dictation.isRecording ? Color.red : Color.brandViolet).opacity(0.22), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(ExpandOnPressStyle())
            .accessibilityLabel(dictation.isRecording ? "Stop recording" : "Start voice dictation")
            .accessibilityHint(dictation.isRecording ? "Stops listening and types what you said." : "Starts listening and types what you say.")
            Button {
                guard let text = UIPasteboard.general.string, !text.isEmpty else { showStatus("Clipboard is empty"); return }
                keyboardTypedText = text
                inputVC.textDocumentProxy.insertText(text)
                showStatus("Pasted \u{2014} tap Rewrite")
            } label: {
                Image(systemName: "doc.on.clipboard").font(.system(size: 9))
                    .frame(width: 20, height: 18)
                    .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(ExpandOnPressStyle())
            .accessibilityLabel("Paste")
            .accessibilityHint("Inserts the text you last copied.")

            Divider().frame(height: 14)
            toolbarTrailingContent
        }
        .padding(.horizontal, 5)
        .frame(height: 20)
    }

    /// The old standalone status line and suggestion strip, sharing one
    /// slot: whichever is active fills it, so this never grows the row.
    private var toolbarTrailingContent: some View {
        HStack(spacing: 0) {
            if dictation.isRecording && !dictation.partialText.isEmpty {
                Text("\u{1F3A4} " + dictation.partialText)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !isNumbers && !suggestions.isEmpty {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    if index > 0 { Divider().frame(height: 12) }
                    Button { applySuggestion(suggestion) } label: {
                        Text(suggestion)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Letter keys are square — measured directly off a real iPad running
    /// Apple's own keyboard (~70pt). Apple reaches that size by filling
    /// the screen width with MORE columns, not by stretching fewer, wider
    /// keys — dividing the same width by only 10 (as a plain letter row
    /// would) badly overshoots the real size on anything 12.9"+. Capped
    /// near that measured size so landscape's extra width (see
    /// `isLandscape`) doesn't grow the keys — and with them the whole
    /// keyboard's height — without bound; the key block instead centers
    /// with margins on the sides in landscape, same as real hardware.
    /// iPhone has much less width to begin with, so "fill the width / 10"
    /// alone already lands close to Apple's real iPhone size.
    private var keySize: CGFloat {
        guard keyboardWidth > 0 else { return 34 }
        guard isPad else { return (keyboardWidth - 5 * 9) / 10 }
        // The number row is the widest row: "`~" dual + 12 digit/symbol
        // duals + 1 delete key (1.4x) = 14.4 key-widths, across 13 gaps.
        // Basing the size on any narrower row would let it overflow past
        // the screen edge.
        let widthBased = (keyboardWidth - 13 * 5) / 14.4
        // Raised from 72: on very wide screens (13" iPad landscape) letting
        // every ordinary key grow a modest amount, not just Tab/Shift,
        // matches how Apple actually spreads leftover width across several
        // keys rather than concentrating it into one or two.
        return min(widthBased, 80)
    }

    /// True when the device is in landscape. `keyboardHeight` is this
    /// keyboard view's own small requested height budget (~250-535pt, see
    /// `requestedHeight`), NOT the device's screen height, so it can
    /// never be compared against `keyboardWidth` to detect orientation —
    /// that comparison was always true, in both orientations, which is
    /// why the keyboard was rendering collapsed to a tiny size. Compare
    /// against the widest known portrait width per idiom instead —
    /// landscape is always noticeably wider than that.
    private var isLandscape: Bool {
        guard keyboardWidth > 0 else { return false }
        let widestPortraitWidth: CGFloat = isPad ? 1100 : 500
        return keyboardWidth > widestPortraitWidth
    }

    /// iPad and iPhone use different Apple key layouts: iPad puts delete at
    /// the end of the q-row with shift on both sides of the z-row; iPhone
    /// puts delete at the end of the z-row with shift only on the left.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Set independently of width — the keyboard's overall height is fixed
    /// (see the height constraint in viewDidLoad), so keys can be taller
    /// than they are wide without risking clipping. iPhone in landscape has
    /// the least vertical room of all, so keys shrink the most there.
    ///
    /// The rewrite-result screen keeps these same keys on screen (so you
    /// can type into "Refine") above the rewrite text, its explanation, and
    /// three choice buttons — more content than even the expanded height
    /// budget (see `setContentExpanded`) can fit at full key size, so keys
    /// shrink further there to leave room for the text to actually show.
    private var keyHeight: CGFloat {
        if !previewText.isEmpty {
            return isPad ? 38 : (isLandscape ? 26 : 30)
        }
        // Real hardware key size doesn't change when the same iPad rotates
        // — landscape just has less room for everything else around the
        // keys (handled by hiding the teaching strip etc.), not smaller
        // keys. Square: same value as `keySize`.
        if isPad { return keySize }
        return isLandscape ? 38 : 48
    }
    private var keyAreaWidth: CGFloat { keySize * 10 + 5 * 9 }

    /// Width for the shift/delete keys on the z-row so that row totals
    /// keyAreaWidth exactly (matches the q-row and a-row above it).
    private var letterEdgeKeyWidth: CGFloat { keySize * 1.5 + 2.5 }

    /// Width for the "#+=" key (and the empty space below the moved delete
    /// key) on the numbers row's bottom row so that row totals keyAreaWidth
    /// exactly.
    private var numberEdgeKeyWidth: CGFloat { keySize * 2.5 + 7.5 }

    /// Key size for the numbers page's top row (1234567890-=), sized so that
    /// those 12 keys plus the delete key at the end fill keyAreaWidth —
    /// mirrors the Apple keyboard's hardware-style number row.
    private var numberTopKeySize: CGFloat {
        (keyAreaWidth - 12 * 5 - numberEdgeKeyWidth) / 12
    }

    /// The iPad number row (`compactNumberRow`) is the widest row —
    /// 13 square keys + a 1.4x delete key across 13 gaps — and `keySize`
    /// itself is derived from that row's width. Every other iPad letters-
    /// page row below is built from fewer square keys than that, so its
    /// non-letter edge keys (Tab, Caps Lock, Return, Shift) are widened to
    /// exactly absorb the leftover width — the same "solve for the edge key"
    /// approach `numberEdgeKeyWidth`/`numberTopKeySize` already use for the
    /// numbers page, and how Apple's own keyboard sizes these keys (they
    /// aren't a fixed ratio, they're whatever size makes the row flush).
    ///
    /// On screens wide enough to cap `keySize` at its max (e.g. 13" iPad
    /// landscape), that "leftover width" used to stop at the number row's
    /// own natural width, leaving real unclaimed margin on both sides of
    /// the whole key block instead of reaching the true screen edge —
    /// `letterRowTargetWidth` is that same leftover-absorption idea,
    /// extended to solve against the actual available width instead.
    private var letterRowTargetWidth: CGFloat {
        let natural = 14.4 * keySize + 65
        guard keyboardWidth > 0 else { return natural }
        return max(natural, keyboardWidth - 8)
    }

    /// Tab (q-row) and Caps Lock (a-row) both replace exactly one square
    /// key's worth of leftover width, widened further to reach
    /// `letterRowTargetWidth` exactly — no cap. Fills the full available
    /// width edge to edge on every screen, even if that means these keys
    /// get quite wide on the largest iPads; matching the true screen edge
    /// takes priority over keeping this key a particular proportion.
    private var qRowEdgeKeyWidth: CGFloat {
        letterRowTargetWidth - 13 * keySize - 65
    }

    /// Return (a-row, at the far end) absorbs the rest of that row's
    /// leftover width once `qRowEdgeKeyWidth` (Caps Lock) has taken its
    /// share — algebraically invariant of the target width (the two
    /// exactly cancel out), so this doesn't need updating alongside it.
    private var returnKeyWidth: CGFloat { keySize * 2 + 5 }

    /// Each Shift key (z-row, one on each end) takes half of that row's
    /// leftover width vs. the number row, same uncapped full-width
    /// treatment as `qRowEdgeKeyWidth`.
    private var zRowShiftWidth: CGFloat {
        (letterRowTargetWidth - 11 * keySize - 60) / 2
    }

    private var keyboardSection: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)
            // iPad's letters page sizes itself from its own uniform-size
            // keys (see `keySize`/`iPadLetterRows`) rather than being
            // squeezed into the number-page's `keyAreaWidth` — that width
            // was based on a 10-column row and is too narrow for the
            // 12-13-column rows the letters page actually has now.
            if isPad && !isNumbers {
                centerKeyRows
            } else {
                centerKeyRows.frame(width: keyboardWidth > 0 ? keyAreaWidth : nil)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Row of up to three tappable word completions, shown above the keys
    /// while typing a word — mirrors Apple's predictive QuickType bar.
    ///
    /// Always reserves this row's full height, even with no suggestions —
    /// otherwise the keys below shift up/down every time the suggestion bar
    /// appears or disappears (e.g. on every space or backspace to empty).
    private var centerKeyRows: some View {
        VStack(spacing: 6) {
            if isNumbers {
                if isPad {
                    // iPad: 1234567890-= on row 1 with delete at the end,
                    // matching Apple's iPad number row.
                    HStack(spacing: 5) {
                        letterRow(isSymbols ? ["[","]","{","}","#","%","^","*","+","=","_","\\"] : ["1","2","3","4","5","6","7","8","9","0","-","="], width: numberTopKeySize)
                        deleteKey(width: numberEdgeKeyWidth)
                    }
                    letterRow(isSymbols ? ["§","|","~","≠","<",">","€","£","¥","·"] : ["-","/",":",";","(",")","$","&","@","\""])
                    HStack(spacing: 5) {
                        modifierKey(
                            isSymbols ? "123" : "#+=", width: numberEdgeKeyWidth,
                            accessibilityLabel: isSymbols ? "Numbers" : "More symbols",
                            accessibilityHint: isSymbols ? "Switches back to numbers." : "Switches to more symbols."
                        ) { isSymbols.toggle(); playKeyClick() }
                        letterRow([".",",","?","!","'"])
                        Color.clear.frame(width: numberEdgeKeyWidth, height: keyHeight)
                    }
                } else {
                    // iPhone: plain 1234567890 on row 1, delete at the end
                    // of row 3 — matching Apple's iPhone number row.
                    letterRow(isSymbols ? ["[","]","{","}","#","%","^","*","+","="] : ["1","2","3","4","5","6","7","8","9","0"])
                    letterRow(isSymbols ? ["_","\\","|","~","<",">","€","£","¥","•"] : ["-","/",":",";","(",")","$","&","@","\""])
                    HStack(spacing: 5) {
                        modifierKey(
                            isSymbols ? "123" : "#+=", width: numberEdgeKeyWidth,
                            accessibilityLabel: isSymbols ? "Numbers" : "More symbols",
                            accessibilityHint: isSymbols ? "Switches back to numbers." : "Switches to more symbols."
                        ) { isSymbols.toggle(); playKeyClick() }
                        letterRow([".",",","?","!","'"])
                        deleteKey(width: numberEdgeKeyWidth)
                    }
                }
            } else {
                if isPad {
                    // Apple's iPad keyboard keeps a number row permanently
                    // visible above the letters — you never need to switch
                    // to the "123" page just to type a digit — and appends
                    // extra punctuation keys to the letter rows below.
                    // Every key here is the same square `keySize`, so
                    // nothing needs to shrink to make room; each row is
                    // simply as wide as its own keys need, instead of all
                    // being squeezed into one shared width.
                    compactNumberRow
                    HStack(spacing: 5) {
                        tabKey(width: qRowEdgeKeyWidth)
                        letterRow(["q","w","e","r","t","y","u","i","o","p"])
                        dualCharKey("[", "{", width: keySize)
                        dualCharKey("]", "}", width: keySize)
                        dualCharKey("\\", "|", width: keySize)
                    }
                    HStack(spacing: 5) {
                        capsLockKey(width: qRowEdgeKeyWidth)
                        letterRow(["a","s","d","f","g","h","j","k","l"])
                        dualCharKey(";", ":", width: keySize)
                        dualCharKey("'", "\"", width: keySize)
                        modifierKey(
                            systemImage: "return", width: returnKeyWidth,
                            accessibilityLabel: "Return",
                            accessibilityHint: "Inserts a new line."
                        ) { insertCharacter("\n") }
                    }
                    HStack(spacing: 5) {
                        shiftKey(width: zRowShiftWidth)
                        dualCharKey("`", "~", width: keySize)
                        letterRow(["z","x","c","v","b","n","m"])
                        dualCharKey(",", "<", width: keySize)
                        dualCharKey(".", ">", width: keySize)
                        dualCharKey("/", "?", width: keySize)
                        shiftKey(width: zRowShiftWidth)
                    }
                } else {
                    // iPhone: plain qwertyuiop on row 1, shift on the left
                    // and delete on the right of the z-row — matching
                    // Apple's iPhone letter layout.
                    letterRow(["q","w","e","r","t","y","u","i","o","p"])
                    letterRow(["a","s","d","f","g","h","j","k","l"]).padding(.horizontal, (keySize + 5) / 2)
                    HStack(spacing: 5) {
                        shiftKey(width: letterEdgeKeyWidth)
                        letterRow(["z","x","c","v","b","n","m"])
                        deleteKey(width: letterEdgeKeyWidth)
                    }
                }
            }
            if isPad {
                // Matches Apple's iPad bottom row layout: globe, .?123,
                // dictation mic (ToneLayer's own Hume-powered dictation,
                // since third-party keyboards can't invoke Apple's system
                // dictation), space, .?123, then the dismiss-keyboard
                // chevron. Return already lives at the end of the a-row
                // above, same as Apple's iPad keyboard.
                HStack(spacing: 5) {
                    modifierKey(
                        systemImage: "globe", width: keySize,
                        accessibilityLabel: "Next keyboard",
                        accessibilityHint: "Switches to your other installed keyboards."
                    ) {
                        playKeyClick()
                        inputVC.advanceToNextInputMode()
                    }
                    modeSwitchKey
                    humeMicKey(width: keySize)
                    spaceKey
                    modeSwitchKey
                    hideKeyboardKey(width: keySize)
                }
            } else {
                HStack(spacing: 5) {
                    modifierKey(
                        isNumbers ? "ABC" : "123", width: keySize * 1.3,
                        accessibilityLabel: isNumbers ? "Letters" : "Numbers and symbols",
                        accessibilityHint: isNumbers ? "Switches back to the letter keys." : "Switches to numbers and symbols."
                    ) {
                        isNumbers.toggle(); isSymbols = false
                        if !capsLocked { isShifted = false }
                        playKeyClick()
                    }
                    modifierKey(
                        systemImage: "globe", width: keySize,
                        accessibilityLabel: "Next keyboard",
                        accessibilityHint: "Switches to your other installed keyboards."
                    ) {
                        playKeyClick()
                        inputVC.advanceToNextInputMode()
                    }
                    spaceKey
                    modifierKey(".", width: keySize, accessibilityLabel: "Period", accessibilityHint: "Types a period.") { insertCharacter(".") }
                    modifierKey(
                        systemImage: "return", width: keySize * 1.6,
                        accessibilityLabel: "Return",
                        accessibilityHint: "Inserts a new line."
                    ) { insertCharacter("\n") }
                }
            }
        }
    }

    private func letterRow(_ letters: [String], width: CGFloat? = nil) -> some View {
        HStack(spacing: 5) {
            ForEach(letters, id: \.self) { letter in
                let variants = accentVariants[letter.lowercased()] ?? []
                let display = isShifted && !isNumbers ? letter.uppercased() : letter
                Group {
                    if variants.isEmpty {
                        letterKey(display, id: letter, width: width) { tapLetter(letter) }
                    } else {
                        letterKey(display, id: letter, width: width) { tapLetter(letter) }
                            .contextMenu {
                                ForEach(variants, id: \.self) { variant in
                                    Button(isShifted && !isNumbers ? variant.uppercased() : variant) {
                                        insertCharacter(isShifted && !isNumbers ? variant.uppercased() : variant)
                                        if isShifted && !capsLocked { isShifted = false }
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func tapLetter(_ letter: String) {
        let output = isShifted && !isNumbers ? letter.uppercased() : letter
        insertCharacter(output)
        if isShifted && !capsLocked { isShifted = false }
    }

    /// Deletes the character before the cursor and refreshes the
    /// predictive suggestion bar — shared by the delete key on every page.
    /// While the rewrite result view is showing, keys target
    /// `refineInstruction` instead (see `insertCharacter`) since there's no
    /// host text field on screen to delete from at that point.
    private func deleteBackward() {
        guard previewText.isEmpty else {
            if !refineInstruction.isEmpty { refineInstruction.removeLast() }
            playKeyClick()
            return
        }
        inputVC.textDocumentProxy.deleteBackward()
        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
        playKeyClick()
        updateSuggestions()
        updateAutoCapitalization()
    }

    /// Inserts a character, running autocorrect on the word just finished
    /// when the character is whitespace/punctuation (mirrors the system
    /// keyboard's "fix typo on space" behavior).
    ///
    /// While the rewrite result view is showing (`previewText` non-empty),
    /// there's no host text field on screen — the on-screen keys are still
    /// visible there only to type the "tell it what to fix" refine
    /// instruction, so characters go into `refineInstruction` instead of
    /// the document proxy. A custom keyboard extension can't summon a
    /// system keyboard for a text field that lives inside itself, so this
    /// is the only way to type into that field at all.
    private func insertCharacter(_ s: String) {
        guard previewText.isEmpty else {
            refineInstruction += s
            playKeyClick()
            return
        }
        let proxy = inputVC.textDocumentProxy
        if s == " ", let before = proxy.documentContextBeforeInput, before.hasSuffix(" "),
           let lastTyped = before.dropLast().last, lastTyped.isLetter {
            // Double-tapping space after a word inserts ". " instead,
            // mirroring Apple's keyboard shortcut.
            proxy.deleteBackward()
            proxy.insertText(". ")
            if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
            keyboardTypedText += ". "
            playKeyClick()
            updateSuggestions()
            updateAutoCapitalization()
            return
        }
        if autocorrectTriggers.contains(s) {
            autocorrectLastWord(proxy: proxy)
        }
        proxy.insertText(s)
        keyboardTypedText += s
        playKeyClick()
        updateSuggestions()
        updateAutoCapitalization()
    }

    /// Replaces the word currently being typed with the tapped suggestion
    /// and inserts a trailing space, like tapping a QuickType suggestion.
    private func applySuggestion(_ suggestion: String) {
        let proxy = inputVC.textDocumentProxy
        guard let before = proxy.documentContextBeforeInput else { return }
        let trailing = before.reversed().prefix { $0.isLetter || $0 == "'" }
        let word = String(trailing.reversed())
        for _ in 0..<word.count { proxy.deleteBackward() }
        if keyboardTypedText.hasSuffix(word) {
            keyboardTypedText.removeLast(word.count)
        }
        insertCharacter(suggestion)
        insertCharacter(" ")
    }

    /// Hard guarantee on top of `teachNDTerms` — never autocorrect these
    /// regardless of case or any system-dictionary edge case. An app about
    /// ADHD has to be able to type the word "adhd" without it silently
    /// becoming "add"; this doesn't depend on `UITextChecker.learnWord`
    /// having taken effect.
    private static let neverAutocorrect: Set<String> = ["adhd", "audhd", "cptsd", "ptsd"]

    private func autocorrectLastWord(proxy: UITextDocumentProxy) {
        guard let before = proxy.documentContextBeforeInput else { return }
        let trailing = before.reversed().prefix { $0.isLetter }
        guard trailing.count > 1 else { return }
        let word = String(trailing.reversed())
        guard !Self.neverAutocorrect.contains(word.lowercased()) else { return }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = textChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
        guard misspelled.location != NSNotFound,
              let guesses = textChecker.guesses(forWordRange: misspelled, in: word, language: "en_US"),
              let best = guesses.first else { return }
        let corrected = matchCapitalization(of: word, to: best)
        guard corrected != word else { return }
        for _ in 0..<word.count { proxy.deleteBackward() }
        proxy.insertText(corrected)
        if keyboardTypedText.hasSuffix(word) {
            keyboardTypedText.removeLast(word.count)
            keyboardTypedText += corrected
        }
    }

    private func matchCapitalization(of original: String, to suggestion: String) -> String {
        if original.count > 1, original == original.uppercased() {
            return suggestion.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    /// Fires `action` the instant a finger touches the key (not on release,
    /// like a plain `Button` would) — matching Apple's own keyboard, which
    /// registers on touch-down for responsiveness. This also keeps the
    /// press-preview bubble in sync with the actual keystroke: both now
    /// happen at the same instant instead of the bubble appearing on touch
    /// while the letter only lands after lifting your finger, which read as
    /// laggy/unreliable typing fast.
    ///
    /// `id` tracks the press independently of `title`. Tapping a letter can
    /// itself flip `isShifted` back off mid-gesture (auto-capitalization
    /// turning off after one letter — see `tapLetter`), which re-renders
    /// this same key with a new lowercase `title` *before the finger lifts*.
    /// If `pressedKeyTitle` were tracked by `title`, `onEnded`'s comparison
    /// would then compare the OLD uppercase value against the NEW lowercase
    /// one, never match, and never reset — permanently jamming that key so
    /// it silently stops registering presses for the rest of the session.
    /// `id` defaults to `letter` (case-invariant) at the one call site that
    /// passes it, so the identity used for tracking never changes mid-press
    /// even though the visible `title` does.
    private func letterKey(_ title: String, id: String? = nil, width: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        let keyID = id ?? title
        return Text(title).font(.system(size: 18, weight: .regular))
            .frame(width: width ?? keySize, height: keyHeight)
            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .keycapShadow()
            .keyTapTarget()
            // Grows the key itself on press, on top of the popup bubble
            // above it — scaleEffect is purely visual (doesn't change the
            // frame SwiftUI hit-tests against), so this can't shift where
            // adjacent keys are tappable.
            .scaleEffect(pressedKeyTitle == keyID ? 1.18 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pressedKeyTitle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressedKeyTitle != keyID else { return }
                        pressedKeyTitle = keyID
                        action()
                    }
                    .onEnded { _ in if pressedKeyTitle == keyID { pressedKeyTitle = nil } }
            )
            .accessibilityAddTraits(.isButton)
        .overlay(alignment: .top) {
            if pressedKeyTitle == keyID {
                Text(title)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                    .frame(width: (width ?? keySize) + 14, height: keyHeight + 16)
                    .background(Color.white, in: KeyPopupBubble())
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .offset(y: -(keyHeight + 12))
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeOut(duration: 0.08)))
            }
        }
        .accessibilityLabel("\(title) key")
        .accessibilityHint("Types the letter \(title).")
    }

    private func modifierKey(_ title: String, active: Bool = false, width: CGFloat, accessibilityLabel: String? = nil, accessibilityHint: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .frame(width: width, height: keyHeight)
                .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                // Apple's iPad keyboard keeps every key white, including
                // function keys — only iPhone's keyboard two-tones them
                // gray, so iPad ignores `active` entirely here.
                .background(isPad || active ? Color.white : Color(red: 0.68, green: 0.70, blue: 0.73), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .keycapShadow()
                .keyTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint)
    }

    private func modifierKey(systemImage: String, active: Bool = false, width: CGFloat, accessibilityLabel: String, accessibilityHint: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .semibold))
                .frame(width: width, height: keyHeight)
                .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                // Apple's iPad keyboard keeps every key white, including
                // function keys — only iPhone's keyboard two-tones them
                // gray, so iPad ignores `active` entirely here.
                .background(isPad || active ? Color.white : Color(red: 0.68, green: 0.70, blue: 0.73), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .keycapShadow()
                .keyTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private func playKeyClick() {
        UIDevice.current.playInputClick()
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
    }

    private func shiftKey(width: CGFloat) -> some View {
        modifierKey(
            systemImage: capsLocked ? "capslock.fill" : (isShifted ? "shift.fill" : "shift"),
            active: capsLocked || isShifted,
            width: width,
            accessibilityLabel: capsLocked ? "Caps lock, on" : (isShifted ? "Shift, on" : "Shift"),
            accessibilityHint: "Tap once to capitalize only the next letter. Tap twice quickly to turn on caps lock.",
            action: handleShiftTap
        )
    }

    /// Switches between letters and numbers/symbols — labeled ".?123" to
    /// match Apple's iPad keyboard exactly (iPhone keeps the plain "123").
    private var modeSwitchKey: some View {
        modifierKey(
            isNumbers ? "ABC" : ".?123", width: keySize * 1.3,
            accessibilityLabel: isNumbers ? "Letters" : "Numbers and symbols",
            accessibilityHint: isNumbers ? "Switches back to the letter keys." : "Switches to numbers and symbols."
        ) {
            isNumbers.toggle(); isSymbols = false
            if !capsLocked { isShifted = false }
            playKeyClick()
        }
    }

    /// Apple's hardware-style iPad layout gives Tab its own key at the start
    /// of the q-row, distinct from shift/caps lock.
    private func tabKey(width: CGFloat) -> some View {
        modifierKey(
            systemImage: "arrow.right.to.line",
            width: width,
            accessibilityLabel: "Tab",
            accessibilityHint: "Inserts a tab character."
        ) { insertCharacter("\t") }
    }

    /// Apple's hardware-style iPad layout puts a dedicated Caps Lock key at
    /// the start of the a-row — separate from the two one-shot Shift keys
    /// on the z-row below, which only capitalize the next letter.
    private func capsLockKey(width: CGFloat) -> some View {
        modifierKey(
            systemImage: capsLocked ? "capslock.fill" : "capslock",
            active: capsLocked,
            width: width,
            accessibilityLabel: capsLocked ? "Caps lock, on" : "Caps lock",
            accessibilityHint: "Turns caps lock on or off."
        ) {
            playKeyClick()
            capsLocked.toggle()
            isShifted = capsLocked
        }
    }

    /// Apple's dictation mic slot on the bottom row, filled with ToneLayer's
    /// own Hume-powered voice dictation (same toggle used by the compose
    /// toolbar's mic button) instead of Apple's system dictation, which
    /// third-party keyboards can't call into.
    private func humeMicKey(width: CGFloat) -> some View {
        modifierKey(
            systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.fill",
            active: dictation.isRecording,
            width: width,
            accessibilityLabel: dictation.isRecording ? "Stop recording" : "Start voice dictation",
            accessibilityHint: dictation.isRecording ? "Stops listening and types what you said." : "Starts listening and types what you say."
        ) {
            playKeyClick()
            dictation.toggle { text in
                inputVC.textDocumentProxy.insertText(text)
                keyboardTypedText += text
            }
        }
    }

    /// Third-party keyboards are expected to offer their own way to return
    /// to the previous keyboard/app, since they don't get the system
    /// keyboard's dismiss gesture — matches Apple's own
    /// "keyboard.chevron.compact.down" dismiss icon.
    private func hideKeyboardKey(width: CGFloat) -> some View {
        modifierKey(
            systemImage: "keyboard.chevron.compact.down",
            width: width,
            accessibilityLabel: "Dismiss keyboard",
            accessibilityHint: "Hides the keyboard."
        ) {
            playKeyClick()
            inputVC.dismissKeyboard()
        }
    }

    /// Single tap behaves like Apple's one-shot shift (capitalizes only the
    /// next letter); double-tap also toggles the persistent caps lock, as a
    /// muscle-memory fallback alongside the dedicated `capsLockKey`.
    private func handleShiftTap() {
        playKeyClick()
        let now = Date()
        if let last = lastShiftTap, now.timeIntervalSince(last) < 0.35 {
            capsLocked.toggle()
            isShifted = capsLocked
            lastShiftTap = nil
        } else {
            if capsLocked {
                capsLocked = false
                isShifted = false
            } else {
                isShifted.toggle()
            }
            lastShiftTap = now
        }
    }

    /// Mirrors Apple's auto-capitalization: shift engages automatically at
    /// the start of a text field and after sentence-ending punctuation.
    private func updateAutoCapitalization() {
        guard !capsLocked, !isNumbers else { return }
        guard let before = inputVC.textDocumentProxy.documentContextBeforeInput, !before.isEmpty else {
            isShifted = true
            return
        }
        guard before.hasSuffix(" ") else { return }
        let beforeTrailingSpace = before.dropLast().reversed().drop { $0 == " " }
        if let lastNonSpace = beforeTrailingSpace.first {
            isShifted = [".", "!", "?"].contains(String(lastNonSpace))
        } else {
            isShifted = true
        }
    }

    /// The iPad's permanently-visible number row: each key doubles as its
    /// shifted punctuation twin (1↔!, 2↔@, …, -↔_, =↔+), with delete at
    /// the end — matching Apple's iPad keyboard, which keeps this whole
    /// row visible above the letters instead of behind a "123" page
    /// switch. Same height as the other rows — on a real iPad the number
    /// row isn't a shrunken strip, it's a full row just like the rest.
    private var compactNumberRow: some View {
        let pairs: [(String, String)] = [
            ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"),
            ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"), ("-", "_"), ("=", "+")
        ]
        return HStack(spacing: 5) {
            // Apple's iPad number row starts with "§/±", not "`~" — the
            // backtick/tilde key lives on the z-row instead (see below).
            dualCharKey("§", "±", width: keySize)
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                dualCharKey(pair.0, pair.1, width: keySize)
            }
            // Same 13-square-keys-plus-one-edge-key shape as the q-row
            // below (13*keySize+65 base), so reuses qRowEdgeKeyWidth's
            // exact formula — keeps this row's total width matching the
            // letter rows below it instead of stopping short of them.
            deleteKey(width: qRowEdgeKeyWidth)
        }
    }

    /// A physical-keyboard-style punctuation key showing two characters:
    /// tapping types the bottom one (or the top one when shift is on,
    /// same as every other key); long-pressing always types the top one
    /// directly, so reaching a symbol never requires a separate tap on
    /// shift first.
    private func dualCharKey(_ bottom: String, _ top: String, width: CGFloat, height: CGFloat? = nil) -> some View {
        VStack(spacing: 0) {
            Text(top).font(.system(size: 10, weight: .regular)).opacity(0.55)
            Text(bottom).font(.system(size: 15, weight: .regular))
        }
        .frame(width: width, height: height ?? keyHeight)
        .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .keycapShadow()
        .keyTapTarget()
        .onTapGesture {
            let typed = isShifted ? top : bottom
            insertCharacter(typed)
            if isShifted && !capsLocked { isShifted = false }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            insertCharacter(top)
        }
        .accessibilityLabel("\(bottom) key")
        .accessibilityHint("Types \(bottom). Long-press to type \(top) directly.")
        .accessibilityAddTraits(.isButton)
    }

    /// Delete key with Apple's long-press auto-repeat behavior.
    private func deleteKey(width: CGFloat, height: CGFloat? = nil) -> some View {
        Image(systemName: "delete.left")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
            .frame(width: width, height: height ?? keyHeight)
            .background(isPad ? Color.white : Color(red: 0.68, green: 0.70, blue: 0.73), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .keycapShadow()
            .keyTapTarget()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard deleteTimer == nil else { return }
                        deleteBackward()
                        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            deleteTimer?.invalidate()
                            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
                                deleteBackward()
                            }
                        }
                    }
                    .onEnded { _ in
                        deleteTimer?.invalidate()
                        deleteTimer = nil
                    }
            )
            .accessibilityLabel("Delete")
            .accessibilityHint("Removes the character before the cursor. Press and hold to delete repeatedly.")
            .accessibilityAddTraits(.isButton)
    }

    /// Space bar: tap inserts a space; a horizontal drag moves the cursor,
    /// mirroring Apple's space-bar trackpad gesture.
    private var spaceKey: some View {
        Text("").font(.system(size: 13, weight: .regular))
            .frame(maxWidth: .infinity).frame(height: keyHeight)
            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
            .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .keycapShadow()
            .keyTapTarget()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard previewText.isEmpty else { return }
                        let dx = value.translation.width
                        let step: CGFloat = 8
                        let target = Int((dx - spaceDragAccumulated) / step)
                        if target != 0 {
                            inputVC.textDocumentProxy.adjustTextPosition(byCharacterOffset: target)
                            spaceDragAccumulated += CGFloat(target) * step
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) < 4 {
                            insertCharacter(" ")
                        }
                        spaceDragAccumulated = 0
                    }
            )
            .accessibilityLabel("Space")
            .accessibilityHint("Inserts a space. Drag left or right to move the cursor.")
            .accessibilityAddTraits(.isButton)
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
                .foregroundStyle(primary ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                .background(primary ? Color.brandVioletDark : Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(primary ? "Uses this rewritten version." : "Keeps your text without the full rewrite.")
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
        profileDyslexic = defaults?.bool(forKey: "ndprofile.dyslexic") ?? false
        let stored = defaults?.string(forKey: "rewriteLevel") ?? "Medium"
        level = ["Light", "Medium", "Strong"].contains(stored) ? stored : "Medium"
        spiralEnabled = defaults?.object(forKey: "spiralPauseEnabled") == nil ? true : (defaults?.bool(forKey: "spiralPauseEnabled") ?? true)
        showExpl = defaults?.object(forKey: "showExplanation.v2") == nil ? true : (defaults?.bool(forKey: "showExplanation.v2") ?? true)
        teachingBody = defaults?.string(forKey: "lastTeachingNote") ?? ""
    }

    /// `UITextDocumentProxy.documentContextBeforeInput`/`AfterInput` only
    /// ever expose a small, roughly fixed-size window of text right around
    /// the cursor, not the whole field — a hard iOS platform limit. For a
    /// long pasted message, that window is just the tail end nearest the
    /// cursor, which is exactly why rewriting only picked up "the very
    /// last bit" of a pasted message.
    ///
    /// The fix: walk the cursor backward, prepending each freshly-read
    /// window and moving back by exactly that window's own reported
    /// length — never a fixed guessed amount. `adjustTextPosition` silently
    /// clamps near the start of the document with no way to detect that it
    /// happened; an earlier version moved back by a fixed guessed `step`
    /// and always counted the full `step` toward the eventual cursor
    /// restore, so on any field shorter than a clean multiple of `step`
    /// the final restore overshot past the original cursor position —
    /// landing later edits in the wrong place in the document. Using each
    /// window's own length as the move amount guarantees the move can
    /// never be clamped short, so the running total always matches the
    /// real distance traveled. Finally, the cursor is restored to exactly
    /// where it started.
    private func seedTypedTextFromProxy() {
        guard keyboardTypedText.isEmpty else { return }
        let proxy = inputVC.textDocumentProxy
        let after = proxy.documentContextAfterInput ?? ""

        var accumulated = ""
        var movedBack = 0
        for _ in 0..<250 {
            guard let window = proxy.documentContextBeforeInput, !window.isEmpty else { break }
            accumulated = window + accumulated
            proxy.adjustTextPosition(byCharacterOffset: -window.count)
            movedBack += window.count
            if window.count < 15 { break }
        }
        if movedBack > 0 {
            proxy.adjustTextPosition(byCharacterOffset: movedBack)
        }
        keyboardTypedText = accumulated + after
    }

    /// Coarse "does this look like real language, not garbled/placeholder
    /// text" check, reusing the on-device `UITextChecker` already used for
    /// suggestions. Guards against captured text that came from a field
    /// that isn't a real message body (e.g. a Messages "To:" recipient
    /// field) rather than requiring the field's role to be known — iOS
    /// gives keyboard extensions no public API to ask "what kind of field
    /// is this," so a garbled short capture like "Ffu" from the wrong
    /// field previously got sent to the AI as if it were a real message,
    /// producing a confusing model-generated response instead of a plain
    /// local status message.
    private func looksLikeRealText(_ text: String) -> Bool {
        let words = text.split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return false }
        for word in words where word.count >= 2 {
            let range = NSRange(location: 0, length: word.utf16.count)
            let bad = spellChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
            if bad.location == NSNotFound { return true }
        }
        return false
    }

    private func rewrite() {
        defaults?.synchronize()
        isRewriting = true; explanation = ""; showSpiral = false
        previewText = ""; pendingDeleteCount = 0
        showStatus("Reading your message\u{2026}")
        defaults?.set(true, forKey: "keyboardRewriteInProgress")
        defaults?.synchronize()
        let tone = dictation.humeTone.toneSummary
        let voiceDistressed = dictation.humeTone.isDistressed
        dictation.humeTone.reset()
        let proxy = inputVC.textDocumentProxy
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
            } else if let clip = pasteboardFullText(before: before, after: after) {
                full = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                totalToDelete = clip.count
            } else {
                let scanned = await captureFullDocument(proxy)
                if scanned.incomplete {
                    await MainActor.run {
                        isRewriting = false
                        defaults?.set(false, forKey: "keyboardRewriteInProgress")
                        defaults?.synchronize()
                        showStatus("Could only read the last part of your message — open it in the ToneLayer app to rewrite the whole thing")
                    }
                    return
                }
                full = scanned.text.trimmingCharacters(in: .whitespacesAndNewlines)
                totalToDelete = scanned.text.count
            }

            guard !full.isEmpty, looksLikeRealText(full) else {
                await MainActor.run {
                    isRewriting = false
                    defaults?.set(false, forKey: "keyboardRewriteInProgress")
                    defaults?.synchronize()
                    showStatus(full.isEmpty ? "Type some text first" : "Couldn't find a real message to rewrite \u{2014} make sure you're typing in the message field")
                }
                return
            }
            await MainActor.run { showStatus("Sending \(full.count) chars\u{2026}") }
            do {
                let result = try await router.rewrite(
                    text: full,
                    profile: activeProfileLabel,
                    level: level,
                    mode: "tonelayer",
                    tone: tone,
                    voiceDistressed: voiceDistressed,
                    allowOnDevice: true
                )
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
                        previewSource = result.source
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

    /// Tries the clipboard as a fast, reliable stand-in for walking the cursor
    /// through `documentContextBeforeInput` when the field's text didn't come
    /// from typing on this keyboard (i.e. it was pasted). Reading
    /// `UIPasteboard.general.string` triggers iOS's own "pasted from" banner —
    /// that's intentional platform behavior telling the user their clipboard
    /// was read, not something to route around. Only trusted when it verifiably
    /// matches what's on screen (cursor at the true end, and the clipboard
    /// string's tail lines up with the visible window), so stale or unrelated
    /// clipboard content is never mistaken for the field's contents.
    ///
    /// The match is done on a "smart punctuation" normalized copy of both
    /// strings, not the raw text — many host apps auto-convert straight
    /// quotes/dashes into curly/em variants the instant text is pasted, so
    /// the live field can differ from the raw clipboard string by a few
    /// typographic characters even though it's the same content. Comparing
    /// literally would reject a real match and fall back to the weaker
    /// cursor-walk unnecessarily. The original (unnormalized) clipboard
    /// string is still what gets returned and sent for rewriting.
    private func pasteboardFullText(before: String, after: String) -> String? {
        guard after.isEmpty, before.count >= 20 else { return nil }
        // UIPasteboard.general is unreadable without Full Access — checking this
        // explicitly (rather than just letting the read return nil) means we
        // skip straight to the cursor-walk fallback instead of wasting a cycle
        // on a read we already know will fail.
        guard inputVC.hasFullAccess else { return nil }
        guard let clip = UIPasteboard.general.string else { return nil }
        guard normalizedForMatch(clip).hasSuffix(normalizedForMatch(before)) else { return nil }
        return clip
    }

    private func normalizedForMatch(_ s: String) -> String {
        var result = s
        let substitutions: [Character: Character] = [
            "\u{2018}": "'", "\u{2019}": "'",   // curly single quotes -> straight
            "\u{201C}": "\"", "\u{201D}": "\"", // curly double quotes -> straight
            "\u{2013}": "-", "\u{2014}": "-",   // en/em dash -> hyphen
            "\u{2026}": "."                      // ellipsis char -> period (approx)
        ]
        result = String(result.map { substitutions[$0] ?? $0 })
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// iOS hands a keyboard only the text near the cursor — for a long message
    /// that's just the back end, which is why a rewrite could miss the start.
    /// This reads the WHOLE field: move the cursor to the end, then read backward
    /// window by window until no new text appears. Non-destructive (it only reads
    /// and moves the cursor); the result is shown as a preview before anything is
    /// replaced, so a bad capture can never silently overwrite the message.
    private func captureFullDocument(_ proxy: UITextDocumentProxy) async -> (text: String, incomplete: Bool) {
        func readAfter()  async -> String { await MainActor.run { proxy.documentContextAfterInput  ?? "" } }
        func readBefore() async -> String { await MainActor.run { proxy.documentContextBeforeInput ?? "" } }
        func move(_ n: Int) async {
            guard n != 0 else { return }
            await MainActor.run { proxy.adjustTextPosition(byCharacterOffset: n) }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // 1) Move to the very end so every character is "before" the cursor.
        var steps = 0
        var after = await readAfter()
        while !after.isEmpty && steps < 400 {
            await move(after.count)
            after = await readAfter()
            steps += 1
        }
        // 2) Read backward, prepending each new window. An unchanged window can
        //    mean two different things: we've truly reached the start of the
        //    document, or (especially on a real device, where the keyboard
        //    extension and host app are separate processes talking over IPC)
        //    the host app just hasn't caught up to the last `adjustTextPosition`
        //    call yet. Treating the first unchanged read as "reached the start"
        //    is what caused real messages to get cut down to just the last
        //    sentence — this instead gives the host app a few chances, with a
        //    growing delay, before concluding the window is genuinely stuck.
        var full = ""
        var lastWindow = ""
        var stall = 0
        var incomplete = false
        steps = 0
        while steps < 800 {
            let window = await readBefore()
            if window.isEmpty { break }
            if window == lastWindow {
                stall += 1
                if stall >= 5 {
                    // Retried several times with growing delays and the window
                    // never moved — this host app genuinely caps how far back a
                    // keyboard extension can see, not just IPC lag. Report this
                    // so the caller can warn the user instead of silently
                    // rewriting a partial message.
                    incomplete = true
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(stall) * 60_000_000)
                continue
            }
            stall = 0
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
        return (full, incomplete)
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
        let redactionNotice: String?
    }

    private func callNarc(text: String) async throws -> NarcResult {
        let (redactedText, mapping, flaggedKinds) = redactor.redact(text)
        let parsed = try await RewriteRouter.postJSON(url: AppConfig.narcURL, body: ["text": redactedText])

        let summary        = redactor.rehydrate(parsed["summary"] as? String ?? "", mapping: mapping)
        let validation      = redactor.rehydrate(parsed["validation"] as? String ?? "", mapping: mapping)
        let boundaryScript  = redactor.rehydrate(parsed["boundary_script"] as? String ?? "", mapping: mapping)
        let riskLevel       = parsed["risk_level"] as? String ?? ""
        let patterns = (parsed["patterns"] as? [[String: Any]] ?? []).map { p in
            NarcPattern(
                name:        p["name"]        as? String ?? "",
                quote:       redactor.rehydrate(p["quote"] as? String ?? "", mapping: mapping),
                explanation: p["explanation"] as? String ?? "",
                ndImpact:    p["nd_impact"]    as? String ?? ""
            )
        }
        guard !summary.isEmpty || !patterns.isEmpty else { throw NBError.badResponse }
        return NarcResult(riskLevel: riskLevel, summary: summary, patterns: patterns, validation: validation, boundaryScript: boundaryScript, redactionNotice: PIIRedactor.friendlyNotice(for: flaggedKinds))
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
        if let notice = r.redactionNotice { lines.append(notice) }
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

// ClaudeResult, NBError, RewriteEntry, and LogStore now live in
// ToneLayerCore (shared with the main app) — see
// ToneLayerCore/Sources/ToneLayerCore/RewriteModels.swift.
