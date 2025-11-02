//
//  ContentView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var bridgeManager = BridgeManager()
    @State private var hasAutoNavigated = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainMenuView(bridgeManager: bridgeManager)
            .onAppear {
                // When the view appears (app launch or wake), validate any restored connection
                if bridgeManager.connectedBridge != nil {
                    Task {
                        await bridgeManager.validateConnection()
                    }
                } else {
                    // Reset auto-navigation flag when no bridge is connected
                    hasAutoNavigated = false
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // When the scene becomes active again, re-validate the connection
                if newPhase == .active, bridgeManager.connectedBridge != nil {
                    Task {
                        await bridgeManager.validateConnection()
                    }
                }
            }
            .onReceive(bridgeManager.connectionValidationPublisher) { result in
                switch result {
                case .success:
                    print("✅ ContentView: Bridge connection validation succeeded")
                    Task {
                        await bridgeManager.getRooms()
                        await bridgeManager.getZones()
                    }
                case .failure(let message):
                    print("❌ ContentView: Bridge connection validation failed: \(message)")
                    // Reset auto-navigation flag when validation fails
                    hasAutoNavigated = false
                }
            }
    }
}

// MARK: - Array Extension for Average Calculation
extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

#Preview {
    ContentView()
}
