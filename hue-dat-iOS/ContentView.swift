//
//  ContentView.swift
//  hue dat iOS
//
//  Root view and lifecycle manager for iOS app
//

import SwiftUI
import Combine
import HueDatShared

struct ContentView: View {
    @State private var bridgeManager = BridgeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var showConnectionFailedAlert = false
    @State private var connectionFailureMessage = ""
    @State private var isValidatingConnection = false
    @State private var validationMessage = "Connecting to bridge..."
    @State private var isConnectionValidated = false

    // Staleness check for auto-refresh (matches macOS gold standard)
    private let lastRefreshKey = "LastiOSRefreshTimestamp"
    private let refreshThreshold: TimeInterval = 30 * 60  // 30 minutes
    @State private var lastResumeTimestamp: Date?

    // Idle timeout - return to list view after 5 minutes of inactivity
    private let idleTimeoutThreshold: TimeInterval = 5 * 60  // 5 minutes
    @State private var lastBackgroundTimestamp: Date?

    // NotificationCenter observer tokens
    @State private var roomNavObserver: NSObjectProtocol?
    @State private var zoneNavObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                Group {
                    if isConnectionValidated && bridgeManager.connectedBridge != nil {
                        RoomsAndZonesListView_iOS(bridgeManager: bridgeManager)
                    } else {
                        MainMenuView_iOS(bridgeManager: bridgeManager)
                    }
                }
                .navigationDestination(for: HueRoom.self) { room in
                    GroupDetailView_iOS<HueRoom>(groupId: room.id)
                        .environment(bridgeManager)
                }
                .navigationDestination(for: HueZone.self) { zone in
                    GroupDetailView_iOS<HueZone>(groupId: zone.id)
                        .environment(bridgeManager)
                }
            }
            .opacity(isValidatingConnection ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isValidatingConnection)

            // Initial validation loading overlay
            if isValidatingConnection {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                LoadingStepIndicator(
                    currentStep: 1,
                    totalSteps: 1,
                    message: validationMessage
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isValidatingConnection)
        .onAppear {
            // Listen for navigation notifications from search
            roomNavObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("NavigateToRoom"),
                object: nil,
                queue: .main
            ) { notification in
                if let room = notification.userInfo?["room"] as? HueRoom {
                    navigationPath.append(room)
                }
            }

            zoneNavObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("NavigateToZone"),
                object: nil,
                queue: .main
            ) { notification in
                if let zone = notification.userInfo?["zone"] as? HueZone {
                    navigationPath.append(zone)
                }
            }

            // When the view appears (app launch or wake), validate any restored connection
            if bridgeManager.connectedBridge != nil {
                // Check if we have cached rooms or zones
                let hasCachedData = !bridgeManager.rooms.isEmpty || !bridgeManager.zones.isEmpty

                if hasCachedData {
                    // Skip validation loading dialog - we have cached data to show immediately
                    print("✅ Found cached data - skipping validation dialog")
                    isConnectionValidated = true
                    isValidatingConnection = false

                    // Still validate in background to ensure bridge is reachable
                    Task {
                        await bridgeManager.validateConnection()

                        // Start SSE stream after validation
                        await startSSEStream()
                    }
                } else {
                    // No cached data - show validation loading dialog
                    print("⏳ No cached data - showing validation dialog")
                    isValidatingConnection = true
                    validationMessage = "Validating connection..."
                    Task {
                        await bridgeManager.validateConnection()
                    }
                }

                // NOTE: Periodic refresh is started by RoomsAndZonesListView after initial data load
                // to prevent race condition with initial load
            } else {
                // No bridge connected - skip validation loading
                isValidatingConnection = false
            }
        }
        .onDisappear {
            if let obs = roomNavObserver {
                NotificationCenter.default.removeObserver(obs)
                roomNavObserver = nil
            }
            if let obs = zoneNavObserver {
                NotificationCenter.default.removeObserver(obs)
                zoneNavObserver = nil
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
                        if idleTime > idleTimeoutThreshold && !navigationPath.isEmpty {
                            print("⏰ App idle for \(Int(idleTime / 60)) minutes - returning to list view")
                            navigationPath.removeLast(navigationPath.count)
                        }
                    }
                    lastBackgroundTimestamp = nil

                    // App became active - re-validate and reconnect SSE stream
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
            // Hide validation loading overlay
            withAnimation(.easeInOut(duration: 0.3)) {
                isValidatingConnection = false
            }

            switch result {
            case .success:
                print("✅ ContentView: Bridge connection validation succeeded")

                // Mark connection as validated - this triggers view to show RoomsAndZonesListView
                isConnectionValidated = true

                // Start SSE stream (data loading happens in RoomsAndZonesListView)
                Task {
                    await startSSEStream()
                }

            case .failure(let message):
                print("❌ ContentView: Bridge connection validation failed: \(message)")
                // Mark as not validated
                isConnectionValidated = false
                // Store failure message and show alert
                connectionFailureMessage = message
                showConnectionFailedAlert = true
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
            if newValue == nil {
                // Bridge disconnected - reset validation state
                isConnectionValidated = false
            } else if oldValue == nil {
                // New bridge connected - trigger validation to show rooms/zones view
                isValidatingConnection = true
                validationMessage = "Validating connection..."
                Task {
                    await bridgeManager.validateConnection()
                }
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
        try? await Task.sleep(nanoseconds: UInt64(3.0 * 1_000_000_000))

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

        // Guard 1: Enforce minimum delay after resume (3 seconds)
        if let lastResume = lastResumeTimestamp {
            let timeSinceResume = now.timeIntervalSince(lastResume)
            if timeSinceResume < 3.0 {
                // Too soon after resume - schedule delayed check
                Task {
                    try? await Task.sleep(nanoseconds: UInt64((3.0 - timeSinceResume) * 1_000_000_000))
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

        // Update timestamp BEFORE refresh (prevents duplicate calls)
        UserDefaults.standard.set(now, forKey: lastRefreshKey)

        print("🔄 Auto-refreshing data (last refresh > 30 minutes ago or first launch)")
        await bridgeManager.refreshAllData(forceRefresh: false)
    }

}

#Preview {
    ContentView()
}
