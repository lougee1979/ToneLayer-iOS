// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI
import UIKit

extension Color {
    static let brandVioletDark = Color(red: 0.369, green: 0.122, blue: 0.784)
    static let brandViolet     = Color(red: 0.220, green: 0.502, blue: 0.973)
    static let brandGreen      = Color(red: 0.608, green: 0.247, blue: 0.910)
    static let brandWhite      = Color(red: 0.976, green: 0.969, blue: 1.000)
    static let brandGreenMist  = Color(red: 0.882, green: 0.914, blue: 0.996)
    static let brandVioletMist = Color(red: 0.929, green: 0.878, blue: 1.000)
}

enum AppConfig {
    static let serverURL    = "https://tonelayer-server-production.up.railway.app/rewrite"
    static let decodeURL    = "https://tonelayer-server-production.up.railway.app/decode"
    static let analyticsURL = "https://tonelayer-server-production.up.railway.app/analytics"
    static let appToken     = "d731136d97cdd46453e7581465537e0d9aee811512b885c2"
}

extension View {
    func appBackground() -> some View {
        self
            .background(Color(red: 0.945, green: 0.937, blue: 0.984))
            .preferredColorScheme(.light)
    }
}

struct GlassCard: ViewModifier {
    var tint: Color = .brandGreen
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.brandWhite.opacity(0.42), tint.opacity(0.16), Color.brandViolet.opacity(0.14), Color.brandVioletDark.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.brandWhite.opacity(0.78), tint.opacity(0.42), Color.brandViolet.opacity(0.34), Color.brandVioletDark.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard(tint: Color = .brandGreen, cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius))
    }
}

enum ComposerError: LocalizedError {
    case apiFailed(Int); case apiMessage(String); case badResponse
    var errorDescription: String? {
        switch self {
        case .apiFailed(let c):  return "Server error (HTTP \(c))"
        case .apiMessage(let m): return m
        case .badResponse:       return "Unexpected server response"
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct UIKitTextView: UIViewRepresentable {
    @Binding var text: String
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.delegate = context.coordinator
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.text = text
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) { if uiView.text != text { uiView.text = text } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UIKitTextView
        init(_ parent: UIKitTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}
