import SwiftUI

let toneLayerAppGroupID = "group.com.alden.tonelayer"
let agreementAcceptedKey = "betaAgreementAccepted.v1"

func hasAcceptedAgreement() -> Bool {
    UserDefaults(suiteName: toneLayerAppGroupID)?.bool(forKey: agreementAcceptedKey) ?? false
}

struct AgreementGate: View {
    @State private var accepted = false
    @State private var showApp  = false

    var body: some View {
        if showApp {
            ContentView()
        } else {
            agreementScreen
        }
    }

    private var agreementScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.918, green: 0.898, blue: 0.984), Color(red: 0.749, green: 0.820, blue: 0.996)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "yin.yang")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color(red: 0.369, green: 0.122, blue: 0.784))
                    Text("ToneLayer").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.220, green: 0.122, blue: 0.584))
                    Text("Beta Testing Agreement").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.top, 52).padding(.bottom, 24)

                ScrollView {
                    Text(agreementText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.22))
                        .lineSpacing(5)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
                .frame(maxHeight: 380)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)

                VStack(spacing: 16) {
                    Button {
                        accepted.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: accepted ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22))
                                .foregroundStyle(accepted ? Color(red: 0.369, green: 0.122, blue: 0.784) : .secondary)
                                .frame(width: 28)
                            Text("I have read and agree to the ToneLayer Beta Testing Agreement, including use of the ToneLayer keyboard extension.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.22))
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button {
                        guard accepted else { return }
                        UserDefaults(suiteName: toneLayerAppGroupID)?.set(true, forKey: agreementAcceptedKey)
                        withAnimation(.easeInOut(duration: 0.3)) { showApp = true }
                    } label: {
                        Text("Enter ToneLayer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                accepted
                                    ? Color(red: 0.369, green: 0.122, blue: 0.784)
                                    : Color(red: 0.6, green: 0.6, blue: 0.7)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!accepted)
                    .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private let agreementText = """
ToneLayer Beta Testing Agreement

Last updated: June 2026

Thank you for testing ToneLayer. This agreement covers the ToneLayer app and the ToneLayer keyboard extension. By accepting and entering the app you agree to the following.

1. INTELLECTUAL PROPERTY — THE APP
ToneLayer, including its software, code, design, branding, AI prompts, and all associated content, is the exclusive intellectual property of the developer and is protected by copyright law. You may not copy, reproduce, modify, distribute, reverse-engineer, decompile, or create derivative works from ToneLayer or any of its components without explicit written permission from the developer. Unauthorized use constitutes copyright infringement and may result in legal action.

2. YOU OWN WHAT YOU PROCESS
You confirm that you have the right to share and process any text you enter into ToneLayer or the ToneLayer keyboard. Do not paste or submit text that belongs to someone else or that you do not have explicit permission to use. ToneLayer is not responsible for any copyright or intellectual-property claims arising from text you submit.

3. BETA SOFTWARE — NO WARRANTIES
ToneLayer is beta software. Features may change, crash, or produce unexpected results at any time without notice. Outputs are provided as-is and accuracy is not guaranteed. The developer is not liable for any direct or indirect loss, harm, or misunderstanding resulting from use during the beta period.

4. NOT A SUBSTITUTE FOR PROFESSIONAL HELP
ToneLayer is a communication aid. It is not a medical device, therapy tool, diagnostic service, or source of legal advice. It does not provide clinical, psychological, or legal guidance. If you need professional support, please speak with a qualified professional.

5. YOUR TEXT IS PROCESSED ON OUR SERVER
Messages you type in the app or keyboard are sent to tonelayer.app for AI processing. Your text is not permanently stored on the server. Do not enter sensitive personal information such as passwords, financial data, or private medical details. By using ToneLayer you consent to this processing.

6. FEEDBACK
As a beta tester you agree to report bugs, usability issues, and unexpected behavior using the feedback option in the app. Your feedback directly improves the app.

7. CONFIDENTIALITY
Please do not share screenshots or video of beta features publicly without permission from the developer.

8. CHANGES TO THIS AGREEMENT
This agreement may be updated before general release. You will be asked to re-read and accept any material changes.

If you have questions, contact the developer through the app or at the support email provided on the App Store listing.

Thank you for helping make ToneLayer better.
"""
}
