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
                // Start periodic refresh when app appears
                bridgeManager.startPeriodicRefresh()
            } else {
                // No bridge configured - stay on setup view
                navigationPath.removeLast(navigationPath.count)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Handle app lifecycle for SSE connection and periodic refresh
            if bridgeManager.connectedBridge != nil {
                switch newPhase {
                case .active:
                    // App became active - re-validate and reconnect SSE stream
                    Task {
                        await bridgeManager.validateConnection()

                        // Reset reconnection backoff when returning from idle
                        await MainActor.run {
                            bridgeManager.reconnectAttempts = 0
                        }

                        // Attempt to reconnect if not already connected
                        if !bridgeManager.isSSEConnected {
                            print("🔄 App became active - attempting SSE reconnection")
                            await startSSEStream()
                        }
                    }
                    // Start periodic refresh when app becomes active
                    bridgeManager.startPeriodicRefresh()

                case .background, .inactive:
                    // App going to background/inactive - stop SSE and periodic refresh to save battery
                    stopSSEStream()
                    bridgeManager.stopPeriodicRefresh()

                @unknown default:
                    break
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

                // Start SSE stream (data loading happens in RoomsAndZonesListView)
                Task {
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
            Button("Use Demo Mode") {
                bridgeManager.enableDemoMode()
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
        // Demo mode: Skip SSE stream
        if bridgeManager.isDemoMode {
            print("🎭 startSSEStream: Demo mode - skipping SSE")
            return
        }

        guard let baseUrl = bridgeManager.connectedBridge?.bridge.displayAddress,
              let username = bridgeManager.connectedBridge?.username else {
            print("⚠️ Cannot start SSE stream: Missing bridge connection details")
            return
        }

        await HueAPIService.shared.setup(baseUrl: baseUrl, hueApplicationKey: username)

        // Start event listener before starting stream
        await MainActor.run {
            bridgeManager.startListeningToSSEEvents()
        }

        do {
            try await HueAPIService.shared.startEventStream()
            print("✅ SSE stream connected")
            // Reset reconnection attempts on successful connection
            await MainActor.run {
                bridgeManager.reconnectAttempts = 0
            }
        } catch {
            print("❌ Failed to start SSE stream: \(error)")
        }
    }

    /// Stop the SSE event stream
    private func stopSSEStream() {
        Task {
            await HueAPIService.shared.stopEventStream()
            await MainActor.run {
                bridgeManager.stopListeningToSSEEvents()
            }
            print("🛑 SSE stream stopped")
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
