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
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var showConnectionFailedAlert = false
    @State private var connectionFailureMessage = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainMenuView(bridgeManager: bridgeManager)
                .navigationDestination(for: String.self) { route in
                    if route == "roomsAndZones" {
                        RoomsAndZonesListView(bridgeManager: bridgeManager)
                    }
                }
        }
        .onAppear {
            // When the view appears (app launch or wake), validate any restored connection
            if bridgeManager.connectedBridge != nil {
                Task {
                    await bridgeManager.validateConnection()
                }
            } else {
                // No bridge configured - stay on setup view
                navigationPath.removeLast(navigationPath.count)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // When the scene becomes active again, re-validate the connection and reconnect SSE stream
            if newPhase == .active, bridgeManager.connectedBridge != nil {
                Task {
                    await bridgeManager.validateConnection()
                    await startSSEStream()
                }
            }
        }
        .onReceive(bridgeManager.connectionValidationPublisher) { result in
            switch result {
            case .success:
                print("✅ ContentView: Bridge connection validation succeeded")
                // Navigate to rooms and zones view
                if navigationPath.isEmpty {
                    navigationPath.append("roomsAndZones")
                }

                // Refresh data and start SSE stream
                Task {
                    async let roomsRefresh: Void = bridgeManager.getRooms()
                    async let zonesRefresh: Void = bridgeManager.getZones()
                    async let scenesRefresh: Void = bridgeManager.fetchScenes()

                    // Wait for all data refresh to complete
                    _ = await (roomsRefresh, zonesRefresh, scenesRefresh)

                    // Start SSE stream after data is loaded
                    await startSSEStream()
                }

            case .failure(let message):
                print("❌ ContentView: Bridge connection validation failed: \(message)")
                // Store failure message and show alert
                connectionFailureMessage = message
                showConnectionFailedAlert = true
                // Navigate back to setup view
                if !navigationPath.isEmpty {
                    navigationPath.removeLast(navigationPath.count)
                }
            }
        }
        .alert("Bridge Connection Failed", isPresented: $showConnectionFailedAlert) {
            Button("Retry") {
                Task {
                    await bridgeManager.validateConnection()
                }
            }
            Button("Disconnect Bridge", role: .destructive) {
                bridgeManager.disconnectBridge()
            }
        } message: {
            Text(connectionFailureMessage.isEmpty ? "Unable to connect to your Hue bridge. The bridge may have a new IP address or be unreachable." : connectionFailureMessage)
        }
        .onChange(of: bridgeManager.connectedBridge) { oldValue, newValue in
            // When bridge is disconnected, navigate back to setup view
            if newValue == nil {
                navigationPath.removeLast(navigationPath.count)
            }
        }
    }

    // MARK: - Helper Methods

    /// Start or restart the SSE event stream
    private func startSSEStream() async {
        guard let baseUrl = bridgeManager.connectedBridge?.bridge.displayAddress,
              let username = bridgeManager.connectedBridge?.username else {
            print("⚠️ Cannot start SSE stream: Missing bridge connection details")
            return
        }

        await HueAPIService.shared.setup(baseUrl: baseUrl, hueApplicationKey: username)
        do {
            try await HueAPIService.shared.startEventStream()
            print("✅ SSE stream connected")
        } catch {
            print("❌ Failed to start SSE stream: \(error)")
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

extension Array where Element == Int {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return Double(reduce(0, +)) / Double(count)
    }
}

#Preview {
    ContentView()
}
