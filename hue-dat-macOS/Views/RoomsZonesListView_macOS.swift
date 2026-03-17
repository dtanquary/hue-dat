//
//  RoomsZonesListView_macOS.swift
//  hue dat macOS
//
//  List of rooms and zones for macOS with native controls
//

import SwiftUI
import HueDatShared

struct RoomsZonesListView_macOS: View {
    @Environment(BridgeManager.self) var bridgeManager

    let onRoomSelected: (HueRoom) -> Void
    let onZoneSelected: (HueZone) -> Void
    let onSettingsSelected: () -> Void

    @State private var isTurningOffAll = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Hover states for header buttons
    @State private var isTurnOffHovered = false
    @State private var isRefreshHovered = false
    @State private var isSettingsHovered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                // Show list with skeleton loaders when refreshing with cached data
                // Show loading view only when loading with no cached data
                let hasData = !bridgeManager.rooms.isEmpty || !bridgeManager.zones.isEmpty
                let isLoading = bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones

                if hasData {
                    // Show list (with skeleton if loading)
                    listContent.contentMargins(.top, 60)
                } else if isLoading {
                    // Show loading view only when no cached data
                    loadingView.contentMargins(.top, 60)
                } else {
                    // Show empty view when not loading and no data
                    emptyView.contentMargins(.top, 60)
                }

            }
            VStack(spacing: 0) {
                // Header with title and buttons
                HStack {
                    VStack(alignment: .leading) {
                        Text("Rooms & Zones")
                            .font(.title3)
                            .fontWeight(.semibold)
                        if (bridgeManager.isLoadingZones) {
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(bridgeManager.rooms.count) Room\(bridgeManager.rooms.count == 1 ? "" : "s") & \(bridgeManager.zones.count) Zone\(bridgeManager.zones.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    }

                    Spacer()

                    // SSE status indicator
                    SSEStatusIndicator()
                        .environment(bridgeManager)
                        .padding(6)
                    
                    Button(action: {
                        Task {
                            isTurningOffAll = true
                            let result = await bridgeManager.turnOffAllLights()
                            isTurningOffAll = false
                            
                            switch result {
                            case .success:
                                break // Success - no alert needed
                            case .failure(let error):
                                errorMessage = "Failed to turn off all lights: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    }) {
                        Image(systemName: "moon.fill")
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 36)
                                    .fill(Color.primary.opacity(isTurnOffHovered ? 0.1 : 0))
                            )
                    }
                    .buttonStyle(.borderless)
                    .disabled(bridgeManager.isRefreshing || isTurningOffAll)
                    .help("Turn Off All Lights")
                    .onHover { isTurnOffHovered = $0 }
                    .animation(.easeInOut(duration: 0.15), value: isTurnOffHovered)
                    
                    Button(action: {
                        Task {
                            await bridgeManager.refreshAllData(forceRefresh: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: bridgeManager.isRefreshing)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 36)
                                    .fill(Color.primary.opacity(isRefreshHovered ? 0.1 : 0))
                            )
                    }
                    .buttonStyle(.borderless)
                    .disabled(bridgeManager.isRefreshing)
                    .help("Refresh")
                    .onHover { isRefreshHovered = $0 }
                    .animation(.easeInOut(duration: 0.15), value: isRefreshHovered)
                    
                    Button(action: onSettingsSelected) {
                        Image(systemName: "gear")
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 36)
                                    .fill(Color.primary.opacity(isSettingsHovered ? 0.1 : 0))
                            )
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                    .onHover { isSettingsHovered = $0 }
                    .animation(.easeInOut(duration: 0.15), value: isSettingsHovered)
                }
                .padding()
                .glassEffect(in: .rect)
            }
        }
        .task {
            // Load data only when empty (first launch or after disconnect)
            // Manual refresh button available for subsequent updates
            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                await bridgeManager.refreshAllData()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d.top.filled").symbolEffect(.bounce.byLayer, options: .repeat(.continuous))
                .font(.largeTitle)
            Text("Loading rooms and zones...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Rooms or Zones")
                .font(.title3)
                .fontWeight(.semibold)

            Button("Refresh") {
                Task {
                    await bridgeManager.refreshAllData(forceRefresh: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        let isLoading = bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Rooms Section
                if !bridgeManager.rooms.isEmpty {
                    sectionHeader("Rooms", count: bridgeManager.rooms.count)

                    ForEach(bridgeManager.rooms) { room in
                        GroupRowView_macOS(group: room, isLoading: isLoading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Disable tap during loading
                                if !isLoading {
                                    onRoomSelected(room)
                                }
                            }
                    }
                }

                // Zones Section
                if !bridgeManager.zones.isEmpty {
                    sectionHeader("Zones", count: bridgeManager.zones.count)
                        .padding(.top, bridgeManager.rooms.isEmpty ? 0 : 8)

                    ForEach(bridgeManager.zones) { zone in
                        GroupRowView_macOS(group: zone, isLoading: isLoading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Disable tap during loading
                                if !isLoading {
                                    onZoneSelected(zone)
                                }
                            }
                    }
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Group Row View (unified for rooms and zones)

struct GroupRowView_macOS<T: GroupedLightContainer>: View {
    let group: T
    var isLoading: Bool = false
    @Environment(BridgeManager.self) var bridgeManager
    @State private var isHovered: Bool = false

    private var groupedLight: HueGroupedLight? {
        group.groupedLights?.first
    }

    private var isOn: Bool {
        groupedLight?.on?.on ?? false
    }

    private var brightness: Double? {
        groupedLight?.dimming?.brightness
    }

    private var groupIcon: String {
        if T.isRoom {
            return iconForArchetype(group.metadata.archetype)
        } else {
            return "square.grid.2x2"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: groupIcon)
                .font(.title3)
                .foregroundStyle(isOn ? .yellow : .secondary)
                .frame(width: 24)

            // Name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(group.metadata.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let brightness = brightness {
                    Text("\(brightness.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(brightness))" : String(format: "%.1f", brightness))% brightness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(isOn ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Brightness progress bar background
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: geometry.size.width * (brightness ?? 0) / 100.0)

                        Spacer(minLength: 0)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: brightness)

                // Hover overlay
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        .skeletonLoader(isActive: isLoading)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

#Preview("With Sample Data") {
    @Previewable @State var manager: BridgeManager = {
        let mgr = BridgeManager()

        // Add some sample data to prevent loading state
        let sampleRoom = HueRoom(
            id: "preview-room-1",
            type: "room",
            metadata: HueRoom.RoomMetadata(name: "Living Room", archetype: "living_room"),
            children: [],
            services: [],
            groupedLights: [
                HueGroupedLight(
                    id: "preview-light-1",
                    type: "grouped_light",
                    on: HueGroupedLight.GroupedLightOn(on: true),
                    dimming: HueGroupedLight.GroupedLightDimming(brightness: 75.0),
                    colorTemperature: nil,
                    color: nil
                )
            ]
        )

        let sampleZone = HueZone(
            id: "preview-zone-1",
            type: "zone",
            metadata: HueZone.ZoneMetadata(name: "Downstairs", archetype: "home"),
            children: [],
            services: [],
            groupedLights: [
                HueGroupedLight(
                    id: "preview-light-2",
                    type: "grouped_light",
                    on: HueGroupedLight.GroupedLightOn(on: false),
                    dimming: HueGroupedLight.GroupedLightDimming(brightness: 0.0),
                    colorTemperature: nil,
                    color: nil
                )
            ]
        )

        mgr.rooms = [sampleRoom]
        mgr.zones = [sampleZone]

        return mgr
    }()

    RoomsZonesListView_macOS(
        onRoomSelected: { _ in },
        onZoneSelected: { _ in },
        onSettingsSelected: {}
    )
    .environment(manager)
    .frame(width: 320, height: 480)
}
