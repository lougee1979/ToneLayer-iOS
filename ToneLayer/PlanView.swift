// Copyright (c) 2026 Alden Lougee. All rights reserved.
// Proprietary and confidential. Unauthorized copying, modification,
// distribution, or derivative use is prohibited.

import SwiftUI

struct PlanView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.brandVioletDark)
                    Text("Plan")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.brandGreen)
                    Text("Coming soon")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("This space will become a step-by-step planner built for executive function \u{2014} breaking goals into small next steps, scheduling them, and checking in so nothing falls through the cracks.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .glassCard(tint: .brandGreen)
            }
            .padding()
        }
        .appBackground()
    }
}

#Preview { PlanView() }
