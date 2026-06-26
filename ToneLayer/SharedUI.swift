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

/// Which engine produced a rewrite — and therefore whether the user's text
/// left their phone. We use this to tell the user, plainly, every time.
enum RewritePrivacy {
    case onDevice   // handled on the phone by Apple's on-device model — nothing left
    case offPhone   // sent to ToneLayer's server + Claude — the text left the phone

    var stayedOnPhone: Bool { self == .onDevice }

    var title: String {
        switch self {
        case .onDevice: return "Private — stayed on this phone"
        case .offPhone: return "Sent off your phone to ToneLayer's AI"
        }
    }
    var systemImage: String {
        switch self {
        case .onDevice: return "lock.iphone"
        case .offPhone: return "antenna.radiowaves.left.and.right"
        }
    }
    var tint: Color {
        self == .onDevice ? .brandGreen : Color(red: 0.85, green: 0.55, blue: 0.0)
    }
}

/// A small, honest indicator of where a rewrite was processed. Apple-style:
/// the user is told the moment their text actually leaves the device.
struct PrivacyBadge: View {
    let privacy: RewritePrivacy
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: privacy.systemImage)
            Text(privacy.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(privacy.tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(privacy.tint.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
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
