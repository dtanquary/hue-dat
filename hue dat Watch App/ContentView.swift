//
//  ContentView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine
import HueDatShared

struct ContentView: View {
    @StateObject private var bridgeManager = BridgeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var showConnectionFailedAlert = false
    @State private var connectionFailureMessage = ""

    // Staleness check for auto-refresh (matches macOS gold standard)
    private let lastRefreshKey = "LastWatchOSRefreshTimestamp"
    private let refreshThreshold: TimeInterval = 30 * 60  // 30 minutes
    private let resumeDelay: TimeInterval = 3.0  // Network stabilization delay
    @State private var lastResumeTimestamp: Date?

    // Idle timeout - return to list view after 5 minutes of inactivity
    private let idleTimeoutThreshold: TimeInterval = 5 * 60  // 5 minutes
    @State private var lastBackgroundTimestamp: Date?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainMenuView(bridgeManager: bridgeManager)
                .navigationDestination(for: String.self) { route in
                    if route == "roomsAndZones" {
                        RoomsAndZonesListView(bridgeManager: bridgeManager, navigationPath: $navigationPath)
                    }
                }
                .navigationDestination(for: HueRoom.self) { room in
                    GroupDetailView<HueRoom>(groupId: room.id, bridgeManager: bridgeManager)
                }
                .navigationDestination(for: HueZone.self) { zone in
                    GroupDetailView<HueZone>(groupId: zone.id, bridgeManager: bridgeManager)
                }
        }
        .onAppear {
            // When the view appears (app launch or wake), validate any restored connection
            if bridgeManager.connectedBridge != nil {
                Task {
                    await bridgeManager.validateConnection()
                }
                // NOTE: Periodic refresh is started by RoomsAndZonesListView after initial data load
                // to prevent race condition with initial load
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
                    // Track resume timestamp for staleness check
                    lastResumeTimestamp = Date()

                    // Check if we've been idle for more than 5 minutes - return to list view
                    if let backgroundTime = lastBackgroundTimestamp {
                        let idleTime = Date().timeIntervalSince(backgroundTime)
                        if idleTime > idleTimeoutThreshold && navigationPath.count > 1 {
                            print("⏰ App idle for \(Int(idleTime / 60)) minutes - returning to list view")
                            // Keep only the "roomsAndZones" route, remove detail views
                            while navigationPath.count > 1 {
                                navigationPath.removeLast()
                            }
                        }
                    }
                    lastBackgroundTimestamp = nil

                    // App became active - re-validate and reconnect SSE stream with delay
                    Task {
                        await reconnectSSEAfterResume()
                    }

                    // Check staleness before triggering periodic refresh (macOS gold standard)
                    checkAndRefreshIfNeeded()

                    // Start periodic refresh when app becomes active
                    bridgeManager.startPeriodicRefresh()

                case .background, .inactive:
                    // Track when we went to background for idle timeout check
                    if lastBackgroundTimestamp == nil {
                        lastBackgroundTimestamp = Date()
                    }

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

    /// Reconnect SSE stream after app becomes active (with validation and delay)
    private func reconnectSSEAfterResume() async {
        guard bridgeManager.connectedBridge != nil else {
            print("⚠️ No bridge connected - skipping SSE reconnect after resume")
            return
        }

        print("🔄 Reconnecting SSE after app became active...")

        // Stop existing SSE connection
        await HueAPIService.shared.stopEventStream()

        // Wait for network to stabilize (3 seconds - matches macOS gold standard)
        try? await Task.sleep(nanoseconds: UInt64(resumeDelay * 1_000_000_000))

        // Validate connection before reconnecting SSE
        await bridgeManager.validateConnection()

        // Reset reconnection backoff when returning from idle
        await MainActor.run {
            bridgeManager.reconnectAttempts = 0
        }

        // Only reconnect if validation succeeded
        guard bridgeManager.isConnectionValidated else {
            print("❌ Connection validation failed after resume - not starting SSE")
            return
        }

        // Restart SSE stream
        await startSSEStream()
        print("✅ SSE reconnected after app resume")
    }

    // MARK: - Staleness Check (macOS Gold Standard Pattern)

    /// Check if data refresh is needed based on staleness threshold
    private func checkAndRefreshIfNeeded() {
        let now = Date()

        // Guard: Enforce minimum delay after resume
        if let lastResume = lastResumeTimestamp {
            let timeSinceResume = now.timeIntervalSince(lastResume)
            if timeSinceResume < resumeDelay {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64((resumeDelay - timeSinceResume) * 1_000_000_000))
                    await performRefreshIfStale()
                }
                return
            }
        }

        Task {
            await performRefreshIfStale()
        }
    }

    /// Perform refresh only if data is stale (> 30 minutes old)
    private func performRefreshIfStale() async {
        let now = Date()

        // Check staleness threshold
        let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date
        let dataIsFresh = lastRefresh != nil && now.timeIntervalSince(lastRefresh!) < refreshThreshold

        if dataIsFresh {
            let minutesAgo = Int(now.timeIntervalSince(lastRefresh!) / 60)
            print("⏭️ Data is fresh (last refresh \(minutesAgo) min ago) - skipping auto-refresh")
            return
        }

        // Update timestamp BEFORE refresh
        UserDefaults.standard.set(now, forKey: lastRefreshKey)

        print("🔄 Auto-refreshing data (last refresh > 30 minutes ago or first launch)")
        await bridgeManager.refreshAllData(forceRefresh: false)
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
