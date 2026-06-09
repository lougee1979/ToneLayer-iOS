import UIKit
import SwiftUI
import Speech
import AVFoundation

// MARK: - Brand colors

extension Color {
    static let brandVioletDark = Color(red: 0.04, green: 0.06, blue: 0.22)
    static let brandViolet     = Color(red: 0.02, green: 0.23, blue: 0.98)
    static let brandGreen      = Color(red: 0.06, green: 0.72, blue: 0.70)
    static let brandWhite      = Color(red: 0.97, green: 0.98, blue: 0.98)
}

// MARK: - Dictation

@MainActor
final class DictationManager: ObservableObject {
    @Published var isRecording = false
    @Published var partialText = ""

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

        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        try? audioEngine.prepare()
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
        if !text.isEmpty { onInsert(text); partialText = "" }
    }
}

// MARK: - Principal class

class KeyboardViewController: UIInputViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(inputVC: self))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let top   = host.view.topAnchor.constraint(equalTo: view.topAnchor)
        let bot   = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let lead  = host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trail = host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        [top, bot, lead, trail].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([top, bot, lead, trail])
    }
}

// MARK: - SwiftUI keyboard view

struct KeyboardView: View {
    let inputVC: UIInputViewController

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
    @State private var pendingDeleteCount = 0
    @State private var previewExplanation = ""
    @State private var showSpiral          = false
    @State private var spiralNT            = ""
    @State private var spiralGrammar       = ""
    @State private var spiralOriginal      = ""
    @State private var spiralOriginalCount = 0
    @State private var isAnalyzing         = false
    @StateObject private var dictation     = DictationManager()
    @State private var analyzeMode: AnalyzeMode = .narc

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
            } else if showSpiral {
                spiralCard.transition(.move(edge: .top).combined(with: .opacity))
            } else {
                mainPanel
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .preferredColorScheme(.light)
        .onAppear { loadSettings() }
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
            Image(systemName: "yin.yang")
                .foregroundStyle(Color.brandGreen)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text("ToneLayer").font(.system(size: 11, weight: .bold))
                Text(activeProfileLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 1) {
                Text("ND \u{2192} NT").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandGreen).lineLimit(1)
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
        .padding(.vertical, 6)
    }

    private var mainPanel: some View {
        VStack(spacing: 4) {
            if !previewText.isEmpty {
                rewritePreview
            }
            actionBar
            if dictation.isRecording && !dictation.partialText.isEmpty {
                Text("🎤 " + dictation.partialText)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .lineLimit(2)
            } else if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .lineLimit(1)
            }
            keyboardRows.padding(.horizontal, 4).padding(.bottom, 4)
        }
        .padding(.top, 6)
    }

    private var rewritePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(previewText)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if !previewExplanation.isEmpty {
                    Text(previewExplanation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                chipButton("Keep mine", primary: false) {
                    previewText = ""; pendingDeleteCount = 0; previewExplanation = ""
                }
                chipButton("Use this ✓", primary: true) { applyPreview() }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.brandGreen.opacity(0.35), lineWidth: 1))
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
                        .background(level == l ? Color.brandGreen : Color(UIColor.systemGray4))
                        .foregroundStyle(level == l ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 20)
            Button(action: rewrite) {
                HStack(spacing: 3) {
                    if isRewriting { ProgressView().scaleEffect(0.6).tint(.white) }
                    else { Image(systemName: "sparkles").font(.system(size: 11)) }
                    Text(isRewriting ? "…" : "Rewrite")
                        .font(.system(size: 11, weight: .bold)).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(isRewriting ? Color.brandGreen.opacity(0.55) : Color.brandGreen)
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
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.secondary)
                    .frame(width: 30, height: 28)
                    .background(dictation.isRecording ? Color.red.opacity(0.12) : Color(UIColor.systemGray4))
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

    /// Letter keys are perfect squares — side length derived from the keyboard's
    /// measured width so they always tile evenly across the row (10 keys + 9 gaps).
    private var keySize: CGFloat {
        let spacing: CGFloat = 5
        let columns: CGFloat = 10
        guard keyboardWidth > 0 else { return 34 }
        return (keyboardWidth - spacing * (columns - 1)) / columns
    }

    private var keyHeight: CGFloat { min(keySize, 42) }

    private var keyboardRows: some View {
        VStack(spacing: 6) {
            if isNumbers {
                letterRow(["1","2","3","4","5","6","7","8","9","0"])
                letterRow(["-","/",":",";","(",")","$","&","@","\""])
                HStack(spacing: 5) {
                    modifierKey("#+=", width: keySize * 1.4) {}
                    letterRow([".",",","?","!","'"])
                    modifierKey(systemImage: "delete.left", width: keySize * 1.4) {
                        inputVC.textDocumentProxy.deleteBackward()
                        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                    }
                }
            } else {
                letterRow(["q","w","e","r","t","y","u","i","o","p"])
                letterRow(["a","s","d","f","g","h","j","k","l"]).padding(.horizontal, (keySize + 5) / 2)
                HStack(spacing: 5) {
                    modifierKey(systemImage: isShifted ? "shift.fill" : "shift", active: isShifted, width: keySize * 1.3) { isShifted.toggle() }
                    letterRow(["z","x","c","v","b","n","m"])
                    modifierKey(systemImage: "delete.left", width: keySize * 1.3) {
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
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { keyboardWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in keyboardWidth = newWidth }
            }
        )
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
                .background(active ? Color.brandGreen : Color(UIColor.systemGray4))
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
                .background(active ? Color.brandGreen : Color(UIColor.systemGray4))
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
                chipButton("As-is", primary: false) { spiralOriginal = ""; spiralOriginalCount = 0; showSpiral = false }
                chipButton("Grammar", primary: false) { applySpiral(spiralGrammar.isEmpty ? spiralOriginal : spiralGrammar) }
                chipButton("NT", primary: true) { applySpiral(spiralNT) }
            }
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandGreen.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{2728}  Here's the rewrite \u{2014} want to use it?").font(.system(size: 13, weight: .bold))
            ScrollView {
                Text(previewText)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 110)
            if !previewExplanation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{1F4A1}").font(.system(size: 12))
                    Text(previewExplanation).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                chipButton("Keep mine", primary: false) {
                    previewText = ""; pendingDeleteCount = 0; previewExplanation = ""
                    showStatus("Kept your original")
                }
                chipButton("Use this \u{2713}", primary: true) { applyPreview() }
            }
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandGreen.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{1F4A1}").font(.system(size: 13))
            Text(explanation).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { withAnimation { explanation = "" } } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brandGreen).font(.system(size: 20))
            }
        }
        .padding(12)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.brandGreen.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func chipButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(primary ? Color.brandGreen : Color(UIColor.systemGray4))
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
    }

    private func rewrite() {
        let proxy = inputVC.textDocumentProxy
        defaults?.synchronize()
        let before     = proxy.documentContextBeforeInput ?? ""
        let typedText  = keyboardTypedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cursorText = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldUseTypedText = !typedText.isEmpty && (cursorText.isEmpty || before.hasSuffix(keyboardTypedText))
        let full          = shouldUseTypedText ? typedText  : cursorText
        let totalToDelete = shouldUseTypedText ? keyboardTypedText.count : before.count
        guard !full.isEmpty else { showStatus("Type some text first"); return }
        showStatus("Sending \(full.count) chars\u{2026}")
        isRewriting = true; explanation = ""; showSpiral = false
        previewText = ""; pendingDeleteCount = 0; previewExplanation = ""
        defaults?.set(true, forKey: "keyboardRewriteInProgress")
        defaults?.synchronize()
        Task {
            do {
                let result = try await callServer(text: full)
                if spiralEnabled && result.isSpiraling {
                    await MainActor.run {
                        isRewriting = false
                        spiralNT = result.rewrite; spiralGrammar = result.grammarOnly
                        spiralOriginal = full; spiralOriginalCount = totalToDelete
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
                        if showExpl {
                            previewExplanation = result.explanation.isEmpty ? "Rewritten at \(level) for \(activeProfileLabel)." : result.explanation
                        }
                        withAnimation { previewText = result.rewrite }
                        showStatus("Review it below, then tap \u{201C}Use this\u{201D}")
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

    private func applyPreview() {
        guard !previewText.isEmpty else { return }
        let proxy = inputVC.textDocumentProxy
        let text = previewText
        let deleteCount = pendingDeleteCount
        defaults?.set(true, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
        Task {
            await deleteBackwardChunked(proxy: proxy, count: deleteCount)
            await insertTextChunked(proxy: proxy, text: text)
            await MainActor.run {
                keyboardTypedText = text
                defaults?.set(text, forKey: "testBoxFullText")
                defaults?.set(false, forKey: "keyboardRewriteInProgress"); defaults?.synchronize()
                previewText = ""; pendingDeleteCount = 0; previewExplanation = ""
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

    private func callServer(text: String) async throws -> ClaudeResult {
        var req = URLRequest(url: URL(string: serverURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken,           forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text":    text,
            "profile": activeProfileLabel,
            "level":   level,
            "mode":    "tonelayer"
        ])
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
                    withAnimation { explanation = result }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    showStatus(error.localizedDescription)
                }
            }
        }
    }

    private func callNarc(text: String) async throws -> String {
        let narcURL = "https://tonelayer-server-production.up.railway.app/narc"
        var req = URLRequest(url: URL(string: narcURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appToken,           forHTTPHeaderField: "x-app-token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NBError.apiFailed(0) }
        if http.statusCode != 200 { throw NBError.apiFailed(http.statusCode) }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NBError.badResponse
        }
        if let analysis = parsed["analysis"] as? String, !analysis.isEmpty { return analysis }
        if let summary  = parsed["summary"]  as? String, !summary.isEmpty  { return summary  }
        if let message  = parsed["message"]  as? String, !message.isEmpty  { return message  }
        throw NBError.badResponse
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
