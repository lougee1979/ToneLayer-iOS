//
//  ToneLayerApp.swift
//  ToneLayer
//
//  Created by Alden-Edwin Lougee on 5/3/26.
//

import SwiftUI

@main
struct ToneLayerApp: App {
    var body: some Scene {
        WindowGroup {
            if hasAcceptedAgreement() {
                ContentView()
            } else {
                AgreementGate()
            }
        }
    }
}
