import UIKit
import SwiftUI

// MARK: - Brand colors: violet and green from the ToneLayer icon

extension Color {
    static let brandVioletDark = Color(red: 0.04, green: 0.06, blue: 0.22)
    static let brandViolet = Color(red: 0.02, green: 0.23, blue: 0.98)
    static let brandGreen = Color(red: 0.06, green: 0.72, blue: 0.70)
    static let brandWhite = Color(red: 0.97, green: 0.98, blue: 0.98)
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

        let top = host.view.topAnchor.constraint(equalTo: view.topAnchor)
        let bot = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let lead = host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trail = host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        [top, bot, lead, trail].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([top, bot, lead, trail])
    }
}

// MARK: - SwiftUI keyboard view

struct KeyboardView: View {
    let inputVC: UIInputViewController

    private let appGroupID = "group.com.alden.tonelayer"
    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    @State private var profile      = "Autism"
    @State private var level        = "Medium"
    @State private var isRewriting  = false
    @State private var status       = ""
    @State private var explanation  = ""
    @State private var showExpl     = true
    @State private var spiralEnabled = true
    @State private var isShifted     = false
    @State private var isNumbers     = false
    @State private var keyboardTypedText = ""

    // Spiral card state
    @State private var showSpiral   = false
    @State private var spiralNT     = ""
    @State private var spiralGrammar = ""
    @State private var spiralOriginal = ""
    @State private var spiralOriginalCount = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if showSpiral {
                spiralCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if !explanation.isEmpty && showExpl {
                explanationCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                mainPanel
            }
        }
        .background(
            LinearGradient(
                colors: [Color.brandViolet.opacity(0.12), Color.brandGreen.opacity(0.12), Color(.systemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.light)
        .onAppear { loadSettings() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(Color.brandViolet)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text("ToneLayer")
                    .font(.system(size: 11, weight: .bold))
                Text(profile)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(levelKeyTitle(level))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandGreen)
                .lineLimit(1)
            Spacer()
            Button { inputVC.advanceToNextInputMode() } label: {
                Image(systemName: "globe")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(spacing: 10) {
            // NT level selector
            HStack(spacing: 6) {
                ForEach(["Light", "Medium", "Strong"], id: \.self) { l in
                    Button {
                        level = l
                        defaults?.set(l, forKey: "rewriteLevel")
                    } label: {
                        Text(levelKeyTitle(l))
                            .font(.system(size: 14, weight: level == l ? .bold : .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(level == l ? Color.brandGreen : Color(.tertiarySystemBackground))
                            .foregroundStyle(level == l ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(l) rewrite level")
                }
            }
            .padding(.horizontal, 14)

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Action row
            HStack(spacing: 8) {
                Button(action: rewrite) {
                    HStack(spacing: 6) {
                        if isRewriting {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 13))
                        }
                        Text(isRewriting ? "Working" : "Rewrite")
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(isRewriting ? Color.brandGreen.opacity(0.55) : Color.brandGreen)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isRewriting)

                Button {
                    guard let text = UIPasteboard.general.string, !text.isEmpty else {
                        showStatus("Clipboard is empty")
                        return
                    }
                    keyboardTypedText = text
                    inputVC.textDocumentProxy.insertText(text)
                    showStatus("Pasted \u{2014} tap Rewrite")
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15))
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button { inputVC.textDocumentProxy.insertText("\n"); keyboardTypedText += "\n" } label: {
                    Image(systemName: "return")
                        .font(.system(size: 15))
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    inputVC.textDocumentProxy.deleteBackward()
                    if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 15))
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            keyboardRows
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .padding(.top, 10)
    }

    private var keyboardRows: some View {
        VStack(spacing: 7) {
            if isNumbers {
                letterRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
                letterRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
                HStack(spacing: 5) {
                    modifierKey("#+=", width: 52) {}
                    letterRow([".", ",", "?", "!", "'"])
                    modifierKey(systemImage: "delete.left", width: 52) {
                        inputVC.textDocumentProxy.deleteBackward()
                        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                    }
                }
            } else {
                letterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
                letterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"])
                    .padding(.horizontal, 18)
                HStack(spacing: 5) {
                    modifierKey(systemImage: isShifted ? "shift.fill" : "shift", active: isShifted, width: 48) {
                        isShifted.toggle()
                    }
                    letterRow(["z", "x", "c", "v", "b", "n", "m"])
                    modifierKey(systemImage: "delete.left", width: 48) {
                        inputVC.textDocumentProxy.deleteBackward()
                        if !keyboardTypedText.isEmpty { keyboardTypedText.removeLast() }
                    }
                }
            }
            HStack(spacing: 5) {
                modifierKey(isNumbers ? "ABC" : "123", width: 50) {
                    isNumbers.toggle()
                    isShifted = false
                }
                modifierKey(systemImage: "globe", width: 44) {
                    inputVC.advanceToNextInputMode()
                }
                letterKey("space", fontSize: 13) {
                    inputVC.textDocumentProxy.insertText(" ")
                    keyboardTypedText += " "
                }
                modifierKey(".", width: 38) {
                    inputVC.textDocumentProxy.insertText(".")
                    keyboardTypedText += "."
                }
                modifierKey(systemImage: "return", width: 58) {
                    inputVC.textDocumentProxy.insertText("\n")
                    keyboardTypedText += "\n"
                }
            }
        }
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

    private func letterKey(_ title: String, fontSize: CGFloat = 22, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                .background(keyGlassBackground(tint: .white, active: false))
                .overlay(keyHighlight(tint: .white.opacity(0.55)))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.22), radius: 0, x: 0, y: 1.2)
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(_ title: String, active: Bool = false, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: width, height: 42)
                .foregroundStyle(active ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                .background(keyGlassBackground(tint: active ? .brandGreen : .brandVioletDark, active: active))
                .overlay(keyHighlight(tint: active ? .brandGreen : .brandVioletDark))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 0, x: 0, y: 1.2)
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(systemImage: String, active: Bool = false, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: width, height: 42)
                .foregroundStyle(active ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                .background(keyGlassBackground(tint: active ? .brandGreen : .brandVioletDark, active: active))
                .overlay(keyHighlight(tint: active ? .brandGreen : .brandVioletDark))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 0, x: 0, y: 1.2)
        }
        .buttonStyle(.plain)
    }

    private func keyGlassBackground(tint: Color, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.brandWhite.opacity(active ? 0.45 : 0.64),
                                tint.opacity(active ? 0.22 : 0.08),
                                Color.brandViolet.opacity(active ? 0.16 : 0.08),
                                Color(.systemGray4).opacity(active ? 0.24 : 0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func keyHighlight(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.brandWhite.opacity(0.72), tint.opacity(0.28), Color.brandViolet.opacity(0.18), Color.black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.7
            )
    }

    // MARK: - Spiral card

    private var spiralCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💚  Pause for a sec?")
                .font(.system(size: 13, weight: .bold))
            Text("Your text has some patterns that might land differently than you intend.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                chipButton("As-is", primary: false) {
                    spiralOriginal = ""
                    spiralOriginalCount = 0
                    showSpiral = false
                }
                chipButton("Grammar", primary: false) {
                    applySpiral(spiralGrammar.isEmpty ? spiralOriginal : spiralGrammar)
                }
                chipButton("NT", primary: true) { applySpiral(spiralNT) }
            }
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.brandGreen.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Explanation card

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡").font(.system(size: 13))
            Text(explanation)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { withAnimation { explanation = "" } } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandGreen)
                    .font(.system(size: 20))
            }
        }
        .padding(12)
        .background(Color(red: 0.91, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.brandGreen.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func chipButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(primary ? Color.brandGreen : Color(.systemGray4))
                .foregroundStyle(primary ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func levelKeyTitle(_ value: String) -> String {
        switch value {
        case "Light": return "L"
        case "Medium": return "M"
        case "Strong": return "S"
        default: return value
        }
    }

    // MARK: - Load settings

    private func loadSettings() {
        let p = defaults?.string(forKey: "selectedProfile") ?? "Autism"
        profile = (p == "PTSD") ? "PTSD / CPTSD" : p

        let stored = defaults?.string(forKey: "rewriteLevel") ?? "Medium"
        level = ["Light", "Medium", "Strong"].contains(stored) ? stored : "Medium"

        spiralEnabled = defaults?.object(forKey: "spiralPauseEnabled") == nil
            ? true : (defaults?.bool(forKey: "spiralPauseEnabled") ?? true)
        showExpl = defaults?.object(forKey: "showExplanation") == nil
            ? true : (defaults?.bool(forKey: "showExplanation") ?? true)
    }

    // MARK: - Rewrite

    private func rewrite() {
        let proxy = inputVC.textDocumentProxy
        defaults?.synchronize()
        let before = proxy.documentContextBeforeInput ?? ""
        let typedText = keyboardTypedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cursorText = before.trimmingCharacters(in: .whitespacesAndNewlines)
        // Fall back to tracked typed text when proxy returns nothing (e.g. Mail's rich text editor)
        let shouldUseTypedText = !typedText.isEmpty && (cursorText.isEmpty || before.hasSuffix(keyboardTypedText))
        let full = shouldUseTypedText ? typedText : cursorText
        let totalToDelete = shouldUseTypedText ? keyboardTypedText.count : before.count

        guard !full.isEmpty else { showStatus("Type some text first"); return }

        showStatus("Sending \(full.count) chars\u{2026}")
        isRewriting = true
        explanation = ""
        showSpiral  = false
        defaults?.set(true, forKey: "keyboardRewriteInProgress")
        defaults?.synchronize()

        Task {
            do {
                let result = try await callClaude(text: full)

                await deleteBackwardChunked(proxy: proxy, count: totalToDelete)
                await insertTextChunked(proxy: proxy, text: result.rewrite)
                await MainActor.run {
                    isRewriting = false

                    if spiralEnabled && result.isSpiraling {
                        spiralNT      = result.rewrite
                        spiralGrammar = result.grammarOnly
                        spiralOriginal = full
                        spiralOriginalCount = result.rewrite.count
                    }
                }

                if spiralEnabled && result.isSpiraling {
                    await deleteBackwardChunked(proxy: proxy, count: result.rewrite.count)
                    await insertTextChunked(proxy: proxy, text: full)
                    await MainActor.run {
                        keyboardTypedText = full
                        defaults?.set(full, forKey: "testBoxFullText")
                        defaults?.set(false, forKey: "keyboardRewriteInProgress")
                        defaults?.synchronize()
                        withAnimation { showSpiral = true }
                    }
                } else {
                    await MainActor.run {
                        keyboardTypedText = result.rewrite
                        defaults?.set(result.rewrite, forKey: "testBoxFullText")
                        defaults?.set(false, forKey: "keyboardRewriteInProgress")
                        defaults?.synchronize()
                        if showExpl {
                            let text = result.explanation.isEmpty
                                ? "Rewritten at \(level) level for your \(profile) profile."
                                : result.explanation
                            withAnimation { explanation = text }
                        }
                        showStatus("Rewritten \u{2713}")
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
        let chunkSize = 50
        var remaining = count
        while remaining > 0 {
            let thisChunk = min(chunkSize, remaining)
            await MainActor.run {
                for _ in 0..<thisChunk { proxy.deleteBackward() }
            }
            remaining -= thisChunk
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func moveCursorToEnd(proxy: UITextDocumentProxy, knownTextCount: Int) async {
        await MainActor.run {
            proxy.adjustTextPosition(byCharacterOffset: knownTextCount)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func insertTextChunked(proxy: UITextDocumentProxy, text: String) async {
        let chunkSize = 400
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<next])
            await MainActor.run {
                proxy.insertText(chunk)
            }
            index = next
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func applySpiral(_ text: String) {
        let proxy = inputVC.textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let deleteCount = spiralOriginalCount > 0 ? spiralOriginalCount : before.count
        defaults?.set(true, forKey: "keyboardRewriteInProgress")
        defaults?.synchronize()
        Task {
            await moveCursorToEnd(proxy: proxy, knownTextCount: deleteCount)
            await deleteBackwardChunked(proxy: proxy, count: deleteCount)
            await insertTextChunked(proxy: proxy, text: text)
            await MainActor.run {
                keyboardTypedText = text
                defaults?.set(text, forKey: "testBoxFullText")
                defaults?.set(false, forKey: "keyboardRewriteInProgress")
                defaults?.synchronize()
                spiralOriginal = ""
                spiralOriginalCount = 0
                withAnimation { showSpiral = false }
                showStatus("Applied \u{2713}")
            }
        }
    }

    private func showStatus(_ msg: String) {
        status = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { status = "" }
    }

    // MARK: - Claude API

    struct ClaudeResult {
        let rewrite: String
        let explanation: String
        let distortions: [String]
        let grammarOnly: String
        var isSpiraling: Bool { !distortions.isEmpty }
    }

    private func callClaude(text: String) async throws -> ClaudeResult {
        guard let apiKey = defaults?.string(forKey: "claudeAPIKey"), !apiKey.isEmpty else {
            throw NBError.noKey
        }

        let system = buildSystem()
        let prompt = "Text:\n\(text)\n\nReply with ONLY valid JSON."

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey,           forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",     forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 8192,
            "system":     system,
            "messages":   [["role": "user", "content": prompt]],
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NBError.apiFailed(0) }
        if http.statusCode != 200 {
            if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = errJSON["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw NBError.apiMessage("\(http.statusCode): \(msg.prefix(120))")
            }
            throw NBError.apiFailed(http.statusCode)
        }
        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String
        else { throw NBError.badResponse }

        let cleaned = extractJSON(from: content)
        if let d = cleaned.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let rewrite: String
            if let paras = parsed["paragraphs"] as? [String], !paras.isEmpty {
                rewrite = paras.joined(separator: "\n\n")
            } else if let r = parsed["rewrite"] as? String, !r.isEmpty {
                rewrite = r
            } else {
                rewrite = ""
            }
            if !rewrite.isEmpty {
                return ClaudeResult(
                    rewrite:      rewrite,
                    explanation:  parsed["explanation"]  as? String   ?? "",
                    distortions:  parsed["distortions"]  as? [String] ?? [],
                    grammarOnly:  parsed["grammar_only"] as? String   ?? ""
                )
            }
        }
        return ClaudeResult(
            rewrite: cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation: "", distortions: [], grammarOnly: ""
        )
    }

    private func extractJSON(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNL = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNL)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let openIdx = s.firstIndex(of: "{"),
           let closeIdx = s.lastIndex(of: "}"),
           openIdx < closeIdx {
            return String(s[openIdx...closeIdx])
        }
        return s
    }

    private func buildSystem() -> String {
        let instruction = levelInstruction(level: level, profile: profile)
        let adaptive    = adaptiveContext()
        return """
        You are ToneLayer, a communication assistant that helps neurodivergent people be understood by neurotypical readers. Your job is to translate the structure and signals of ND communication \u{2014} not to delete the person's voice, meaning, or emotional content. Profile: \(profile). \(instruction)\(adaptive)

        Rewrite the entire text the user provided from ND style into NT style. Do not stop halfway, do not summarize only the beginning, and do not omit later points just because the text is long or messy. Preserve the user's intended message, requests, constraints, and necessary context from the whole original, but translate the structure, order, tone, and phrasing into what an NT reader would naturally expect.

        The "paragraphs" rewrite is the primary output. Do not shorten, flatten, or simplify the main rewrite to make room for grammar_only. Generate grammar_only after the main rewrite, and keep it secondary. For any text longer than 3 sentences, you MUST return at least 2 paragraphs in the array \u{2014} never collapse everything into a single string. Brain dumps and multi-topic text must always be organized into multiple paragraphs.

        This is a teaching tool. The explanation must teach \u{2014} don't just say what changed, say WHY that change makes the text land better with NT readers. Help the user recognise their own patterns over time.

        Always respond with ONLY valid JSON \u{2014} no markdown, no code fences, no extra text.

        {
          "paragraphs": ["first paragraph as a plain string", "second paragraph as a plain string", "third paragraph if needed"],
          "explanation": "REQUIRED: one sentence explaining what ND pattern you addressed and why the change makes it more NT-legible.",
          "distortions": ["any cognitive distortions found, e.g. catastrophizing, mind-reading \u{2014} empty array if none"],
          "grammar_only": "secondary option: grammar-fixed version of the full original that keeps the user's ND structure and meaning but fixes grammar, spelling, punctuation, and obvious typos."
        }
        """
    }

    private func adaptiveContext() -> String {
        let patterns = LogStore.shared.topPatterns()
        guard !patterns.isEmpty else { return "" }
        let list = patterns.map { "\($0.pattern) (\($0.count)\u{d7})" }.joined(separator: ", ")
        return "\n\nThis user's recurring patterns: \(list). Be especially attentive to these."
    }

    // MARK: - Level instructions

    private func levelInstruction(level: String, profile: String) -> String {
        switch profile {

        case "ADHD":
            switch level {
            case "Light":
                return "Make minimal changes. Fix typos and grammar. If the main point is completely buried, move it to the first sentence. Preserve all content and the user's voice. This is a light polish \u{2014} do not cut or restructure."
            case "Medium":
                return "Restructure from ND flow into NT readability. Move the main point to the first sentence. Group related ideas into short paragraphs \u{2014} each paragraph covers one topic. Cut obvious repetition but keep all distinct ideas and the user's voice intact. The rewrite MUST have multiple paragraphs separated by blank lines. NT readers should be able to follow without effort."
            default: // Strong
                return "Reorganize and signal this content clearly for NT readers while keeping the user's voice and meaning fully intact. Lead with what the person needs, is asking, or is communicating. Break into clear paragraphs \u{2014} each covering one idea or thread. Keep the emotional content and the connections between ideas \u{2014} sequence them so they read as deliberate rather than scattered. Do not strip the person's voice, delete their concerns, or flatten the emotional texture. If the text asks for help or describes a struggle, name it clearly in the first paragraph \u{2014} then context and detail follow in subsequent paragraphs. This is translation, not deletion. The output MUST be multiple paragraphs."
            }

        case "Autism":
            switch level {
            case "Light":
                return "Make a light ND-to-NT rewrite. Fix typos. Add a brief greeting or sign-off only if completely absent. Keep all content and voice intact."
            case "Medium":
                return "Make a medium ND-to-NT rewrite. Add appropriate social warmth \u{2014} a genuine greeting, warm transitions, polite closing. Decode any implied meaning and state it directly. Keep all literal content. NT readers should feel connected, not just informed. Use multiple paragraphs to separate distinct topics or points."
            default: // Strong
                return "Make a strong ND-to-NT rewrite using NT social norms. Add natural social flow \u{2014} appropriate opening, warmth throughout, clear closing. Remove overly blunt phrasing where it would land poorly. Preserve all the user's meaning. Break into multiple paragraphs \u{2014} each one covering one idea. Should read as something an NT person would naturally write to build or maintain a relationship."
            }

        case "PTSD / CPTSD":
            switch level {
            case "Light":
                return "Make a light ND-to-NT rewrite. Soften the most reactive or escalating phrases only. Keep all content and the user's voice intact."
            case "Medium":
                return "Make a medium ND-to-NT rewrite. Remove over-justification, excessive apology, and defensive language. Rewrite hedging sentences to be direct. Calm tone throughout. Use multiple paragraphs to organize the content. NT readers should feel a steady, confident person wrote this."
            default: // Strong
                return "Make a strong ND-to-NT rewrite into calm, grounded communication. Remove all defensive language, over-explanation, and anticipatory apology. Break into multiple paragraphs \u{2014} each one making a clear, direct point. Write with quiet confidence \u{2014} what a calm, clear-headed NT person would write with the same message. No escalating language, no hedging."
            }

        case "PTSD + Autism":
            switch level {
            case "Light":
                return "Make a light ND-to-NT rewrite. Soften the most reactive phrases and add a greeting if absent. Minimal changes otherwise."
            case "Medium":
                return "Make a medium ND-to-NT rewrite. Remove over-justification and add social warmth. Direct but kind. Cut defensive hedging while adding genuine warmth and connection. Use multiple paragraphs to separate distinct topics."
            default: // Strong
                return "Make a strong ND-to-NT rewrite: warm, direct, calm, no over-justification, no idioms. Break into multiple paragraphs \u{2014} one idea per paragraph. What a warm, grounded NT person would write with the same message."
            }

        case "PTSD + ADHD":
            switch level {
            case "Light":
                return "Make a light ND-to-NT rewrite. Soften the most reactive phrasing and move the main point closer to the start if buried. Minimal changes otherwise."
            case "Medium":
                return "Make a medium ND-to-NT rewrite. Lead with the main point. Cut the worst tangents. Remove defensive over-explanation. Use multiple paragraphs to organize the message. Calmer and more focused."
            default: // Strong
                return "Reorganize and signal this content clearly for NT readers while keeping the user's voice and meaning intact. Lead with the main point or need. Break into multiple paragraphs \u{2014} each one organized around one topic or thread. Keep emotional content \u{2014} sequence it so it reads as deliberate rather than scattered. Remove defensive language and over-explanation. Calm, organized, and still recognizably the person who wrote it. Output MUST be multiple paragraphs."
            }

        default:
            switch level {
            case "Light":  return "Make a light ND-to-NT rewrite. Fix typos and grammar only. Keep all content and voice intact."
            case "Medium": return "Restructure ND communication into NT-readable clarity. Main point first. Cut obvious repetition. Use multiple paragraphs. Keep the user's voice and all distinct substance."
            default:       return "Fully translate ND communication for NT readers. Clear, direct, organized into multiple paragraphs. What an NT person would naturally write with the same intent, while preserving the whole message."
            }
        }
    }

    // MARK: - Log

    private func saveLog(original: String, result: ClaudeResult) {
        let entry = RewriteEntry(
            id: UUID(), timestamp: Date(),
            profile: profile, mode: level,
            originalText: original, rewrittenText: result.rewrite,
            explanation: result.explanation,
            distortions: result.distortions, spiraling: result.isSpiraling
        )
        DispatchQueue.global(qos: .background).async { LogStore.shared.append(entry) }
    }
}

// MARK: - Errors

enum NBError: LocalizedError {
    case noKey
    case apiFailed(Int)
    case apiMessage(String)
    case badResponse
    var errorDescription: String? {
        switch self {
        case .noKey:                return "No API key \u{2014} add it in the ToneLayer app"
        case .apiFailed(let code):  return "API failed (HTTP \(code))"
        case .apiMessage(let s):    return s
        case .badResponse:          return "Unexpected API response"
        }
    }
}

// MARK: - Shared log model (must match ContentView.swift)

struct RewriteEntry: Codable {
    let id: UUID
    let timestamp: Date
    let profile: String
    let mode: String
    let originalText: String
    let rewrittenText: String
    let explanation: String
    let distortions: [String]
    let spiraling: Bool
}

final class LogStore {
    static let shared = LogStore()
    private let appGroupID = "group.com.alden.tonelayer"
    private let fileName   = "rewrite_log.json"

    private var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    func load() -> [RewriteEntry] {
        guard let url = logURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RewriteEntry].self, from: data)
        else { return [] }
        return entries
    }

    func append(_ entry: RewriteEntry) {
        var entries = load()
        entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        guard let url = logURL,
              let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func topPatterns(limit: Int = 40) -> [(pattern: String, count: Int)] {
        let recent = Array(load().suffix(limit))
        let all = recent.flatMap { $0.distortions }.filter { !$0.isEmpty }
        return Dictionary(grouping: all, by: { $0 })
            .mapValues { $0.count }
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (pattern: $0.key, count: $0.value) }
    }
}
