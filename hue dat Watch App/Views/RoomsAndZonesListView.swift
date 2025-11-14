//
//  RoomsAndZonesListView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI
import HueDatShared

struct RoomsAndZonesListView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var hasLoadedData = false
    @State private var rotationAngle: Double = 0
    @State private var showSettings = false
    @State private var showNetworkErrorAlert = false
    @State private var isTurningOffLights = false
    @State private var hasGivenInitialHaptic = false
    @State private var hasGivenFinalHaptic = false
    @State private var hasGivenRefreshInitialHaptic = false
    @State private var hasGivenRefreshFinalHaptic = false

    // Dynamic Type scaled metrics
    @ScaledMetric(relativeTo: .body) private var emptyStateSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var loadingSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var labelIconSpacing: CGFloat = 6

    var body: some View {
        Group {
            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty && !bridgeManager.isRefreshing && hasLoadedData {
                VStack(spacing: emptyStateSpacing) {
                    Image(systemName: "square.3.layers.3d.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No rooms or zones found")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh") {
                        Task {
                            await refreshData()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                List {
                    // Rooms section
                    if !bridgeManager.rooms.isEmpty {
                        Section("Rooms") {
                            ForEach(bridgeManager.rooms) { room in
                                NavigationLink(destination: RoomDetailView(roomId: room.id, bridgeManager: bridgeManager)) {
                                    RoomRowView(room: room)
                                }
                            }
                        }
                    }

                    // Zones section
                    if !bridgeManager.zones.isEmpty {
                        Section("Zones") {
                            ForEach(bridgeManager.zones) { zone in
                                NavigationLink(destination: ZoneDetailView(zoneId: zone.id, bridgeManager: bridgeManager)) {
                                    ZoneRowView(zone: zone)
                                }
                            }
                        }
                    }

                    // Turn Off All Lights section
                    Section("More") {
                        Button {
                            Task {
                                await turnOffAllLights()
                            }
                        } label: {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "lightbulb.slash")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Turn Off All Lights")
                                    .font(.body)
                                Spacer()
                                if isTurningOffLights {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isTurningOffLights || bridgeManager.connectedBridge == nil)
                        
                        Button {
                            Task {
                                await refreshData()
                            }
                        } label: {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Refresh Data")
                                    .font(.body)
                                Spacer()
                                if bridgeManager.isRefreshing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(bridgeManager.isRefreshing || bridgeManager.connectedBridge == nil)

                        // Last refresh timestamp
                        if let lastRefresh = bridgeManager.lastRefreshTimestamp {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Updated \(lastRefresh, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Rooms & Zones")
        .navigationBarTitleDisplayMode(.automatic)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(bridgeManager: bridgeManager)
        }
        .onChange(of: bridgeManager.isRefreshing) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            } else {
                withAnimation {
                    rotationAngle = 0
                }
            }
        }
        .overlay {
            if !hasLoadedData && bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: loadingSpacing) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            // Load data once when first navigating to this view
            // Only load if data is empty (first time or after disconnect)
            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                await refreshData()
            }
            hasLoadedData = true

            // Start periodic refresh AFTER initial load completes
            // This prevents race condition where periodic refresh blocks initial load
            bridgeManager.startPeriodicRefresh()
        }
        .alert("Unable to Load Rooms & Zones", isPresented: $showNetworkErrorAlert) {
            Button("Retry") {
                Task {
                    await refreshData()
                }
            }
            Button("Try Demo Mode") {
                bridgeManager.enableDemoMode()
                Task {
                    await refreshData()
                }
            }
            Button("Disconnect Bridge", role: .destructive) {
                bridgeManager.disconnectBridge()
                // Navigation to MainMenuView happens automatically via ContentView
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(bridgeManager.refreshError ?? "Please check your network connection or try disconnecting and reconnecting to the bridge.")
        }
        .onChange(of: bridgeManager.refreshError) { _, newError in
            // Only show alert if error occurs and we've attempted to load data
            if newError != nil && hasLoadedData {
                showNetworkErrorAlert = true
            }
        }
        .onChange(of: bridgeManager.connectedBridge) { oldBridge, newBridge in
            // When bridge connection changes (disconnect or new bridge), reset state and reload
            if let newBridge = newBridge, oldBridge?.bridge.id != newBridge.bridge.id {
                print("🔄 New bridge detected, resetting view state and loading fresh data")
                hasLoadedData = false
                // The .task modifier will trigger automatically when hasLoadedData changes
            }
        }
    }

    private func refreshData() async {
        // Give initial haptic feedback
        if !hasGivenRefreshInitialHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenRefreshInitialHaptic = true
        }

        // Refresh rooms, zones, and scenes in parallel
        // isRefreshing state is now managed by BridgeManager
        async let roomsRefresh: Void = bridgeManager.getRooms()
        async let zonesRefresh: Void = bridgeManager.getZones()
        async let scenesRefresh: Void = bridgeManager.fetchScenes()

        // Wait for all to complete
        _ = await (roomsRefresh, zonesRefresh, scenesRefresh)

        // Give success haptic
        if !hasGivenRefreshFinalHaptic {
            WKInterfaceDevice.current().play(.success)
            hasGivenRefreshFinalHaptic = true
        }

        hasLoadedData = true

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hasGivenRefreshInitialHaptic = false
            hasGivenRefreshFinalHaptic = false
        }
    }

    private func turnOffAllLights() async {
        // Give initial haptic feedback
        if !hasGivenInitialHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialHaptic = true
        }

        isTurningOffLights = true

        let result = await bridgeManager.turnOffAllLights()

        switch result {
        case .success:
            // Give success haptic
            if !hasGivenFinalHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalHaptic = true
            }

        case .failure(let error):
            print("❌ Failed to turn off all lights: \(error.localizedDescription)")
            // Give failure haptic
            WKInterfaceDevice.current().play(.failure)
        }

        isTurningOffLights = false

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hasGivenInitialHaptic = false
            hasGivenFinalHaptic = false
        }
    }
}

// MARK: - Room Row View
struct RoomRowView: View {
    let room: HueRoom

    // Dynamic Type scaled metrics
    @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var nameSpacing: CGFloat = 2
    @ScaledMetric(relativeTo: .caption) private var statusSpacing: CGFloat = 2
    @ScaledMetric(relativeTo: .caption) private var statusDotSpacing: CGFloat = 4
    @ScaledMetric(relativeTo: .caption) private var statusDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 2

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = room.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            Image(systemName: iconForArchetype(room.metadata.archetype))
                .font(.headline)
                .foregroundStyle(lightStatus.isOn ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: nameSpacing) {
                Text(room.metadata.name)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: statusSpacing) {
                HStack(spacing: statusDotSpacing) {
                    Circle()
                        .fill(lightStatus.isOn ? Color.green : Color.secondary)
                        .frame(width: statusDotSize, height: statusDotSize)
                    Text(lightStatus.isOn ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(lightStatus.isOn ? .primary : .secondary)
                }

                if let brightness = lightStatus.brightness {
                    
                    Text("\(Int(brightness))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, verticalPadding)
    }

    private func iconForArchetype(_ archetype: String) -> String {
        switch archetype.lowercased() {
        case "living_room": return "sofa"
        case "bedroom": return "bed.double"
        case "kitchen": return "fork.knife"
        case "bathroom": return "drop"
        case "office": return "desktopcomputer"
        case "dining": return "fork.knife"
        case "hallway": return "door.left.hand.open"
        case "toilet": return "drop"
        case "garage": return "car"
        case "terrace", "balcony": return "sun.max"
        case "garden": return "leaf"
        case "gym": return "figure.run"
        case "recreation": return "gamecontroller"
        default: return "square.split.bottomrightquarter"
        }
    }
}

// MARK: - Zone Row View
struct ZoneRowView: View {
    let zone: HueZone

    // Dynamic Type scaled metrics
    @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var nameSpacing: CGFloat = 2
    @ScaledMetric(relativeTo: .caption) private var statusSpacing: CGFloat = 2
    @ScaledMetric(relativeTo: .caption) private var statusDotSpacing: CGFloat = 4
    @ScaledMetric(relativeTo: .caption) private var statusDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 2

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = zone.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            Image(systemName: "square.3.layers.3d")
                .font(.headline)
                .foregroundStyle(lightStatus.isOn ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: nameSpacing) {
                Text(zone.metadata.name)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: statusSpacing) {
                HStack(spacing: statusDotSpacing) {
                    Circle()
                        .fill(lightStatus.isOn ? Color.green : Color.secondary)
                        .frame(width: statusDotSize, height: statusDotSize)
                    Text(lightStatus.isOn ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(lightStatus.isOn ? .primary : .secondary)
                }

                if let brightness = lightStatus.brightness {
                    Text("\(Int(brightness))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, verticalPadding)
    }
}
