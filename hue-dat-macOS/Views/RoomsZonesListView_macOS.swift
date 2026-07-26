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
    @State private var searchText = ""
    @State private var searchManager: SearchManager?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchResults: SearchResults? {
        guard isSearching else { return nil }
        return searchManager?.search(searchText)
    }

    private var displayedRooms: [HueRoom] {
        searchResults?.rooms ?? bridgeManager.rooms
    }

    private var displayedZones: [HueZone] {
        searchResults?.zones ?? bridgeManager.zones
    }

    var body: some View {
        Group {
            // Show list with skeleton loaders when refreshing with cached data
            // Show loading view only when loading with no cached data
            let hasData = !bridgeManager.rooms.isEmpty || !bridgeManager.zones.isEmpty
            let isLoading = bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones

            if hasData {
                listContent
            } else if isLoading {
                loadingView
            } else {
                emptyView
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PanelHeader(title: "Rooms & Zones", subtitle: subtitle, searchText: $searchText) {
                SSEStatusIndicator()
                    .environment(bridgeManager)
                    .padding(.trailing, 4)

                Button {
                    turnOffAllLights()
                } label: {
                    Image(systemName: "moon.fill")
                }
                .buttonStyle(.borderless)
                .headerButtonHover()
                .disabled(bridgeManager.isRefreshing || isTurningOffAll)
                .help("Turn Off All Lights")
                .accessibilityLabel("Turn Off All Lights")

                Button {
                    Task {
                        await bridgeManager.refreshAllData(forceRefresh: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: bridgeManager.isRefreshing)
                }
                .buttonStyle(.borderless)
                .headerButtonHover()
                .disabled(bridgeManager.isRefreshing)
                .help("Refresh")
                .accessibilityLabel("Refresh")

                Button(action: onSettingsSelected) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .headerButtonHover()
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .onAppear {
            if searchManager == nil {
                searchManager = SearchManager(bridgeManager: bridgeManager)
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

    private var subtitle: String {
        if bridgeManager.isLoadingZones {
            return "Loading..."
        }
        return "\(bridgeManager.rooms.count) Room\(bridgeManager.rooms.count == 1 ? "" : "s") & \(bridgeManager.zones.count) Zone\(bridgeManager.zones.count == 1 ? "" : "s")"
    }

    private func togglePower<G: GroupedLightContainer>(for group: G) {
        guard let lightId = group.services?.first(where: { $0.rtype == "grouped_light" })?.rid,
              let light = group.groupedLights?.first else { return }
        let oldValue = light.on?.on ?? false
        let newValue = !oldValue

        // Optimistic update: rows render straight from bridgeManager.rooms/zones,
        // SSE echo confirms (no post-action refresh, per project convention)
        if G.isRoom {
            bridgeManager.updateLocalRoomState(roomId: group.id, on: newValue)
        } else {
            bridgeManager.updateLocalZoneState(zoneId: group.id, on: newValue)
        }

        Task {
            let result = await bridgeManager.setGroupedLightPower(id: lightId, on: newValue)
            if case .failure(let error) = result {
                if G.isRoom {
                    bridgeManager.updateLocalRoomState(roomId: group.id, on: oldValue)
                } else {
                    bridgeManager.updateLocalZoneState(zoneId: group.id, on: oldValue)
                }
                errorMessage = "Couldn't toggle \(group.metadata.name): \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func turnOffAllLights() {
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
                if !displayedRooms.isEmpty {
                    sectionHeader("Rooms", count: displayedRooms.count)

                    ForEach(displayedRooms) { room in
                        Button {
                            onRoomSelected(room)
                        } label: {
                            GroupRowView_macOS(group: room, isLoading: isLoading) {
                                togglePower(for: room)
                            }
                        }
                        .buttonStyle(PressableRowStyle())
                        .disabled(isLoading)
                    }
                }

                // Zones Section
                if !displayedZones.isEmpty {
                    sectionHeader("Zones", count: displayedZones.count)
                        .padding(.top, displayedRooms.isEmpty ? 0 : 8)

                    ForEach(displayedZones) { zone in
                        Button {
                            onZoneSelected(zone)
                        } label: {
                            GroupRowView_macOS(group: zone, isLoading: isLoading) {
                                togglePower(for: zone)
                            }
                        }
                        .buttonStyle(PressableRowStyle())
                        .disabled(isLoading)
                    }
                }

                // Scenes Section (search results only) - navigates to the owning room/zone
                if let sceneResults = searchResults?.scenes, !sceneResults.isEmpty {
                    sectionHeader("Scenes", count: sceneResults.count)
                        .padding(.top, (displayedRooms.isEmpty && displayedZones.isEmpty) ? 0 : 8)

                    ForEach(sceneResults, id: \.scene.id) { result in
                        Button {
                            if let room = result.associatedRoom {
                                onRoomSelected(room)
                            } else if let zone = result.associatedZone {
                                onZoneSelected(zone)
                            }
                        } label: {
                            sceneResultRow(result)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isSearching, searchResults?.isEmpty ?? false {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 24)
                }
            }
            .padding()
        }
    }

    private func sceneResultRow(_ result: SceneSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "theatermasks")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.scene.metadata.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let context = result.contextDescription {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
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
    var onTogglePower: (() -> Void)? = nil
    @Environment(BridgeManager.self) var bridgeManager
    @State private var isHovered: Bool = false

    private var groupedLight: HueGroupedLight? {
        group.groupedLights?.first
    }

    /// Live color the group's lights are actually showing right now
    private var liveColor: Color {
        groupedLight?.displayColor ?? .orange
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
            // Icon doubles as inline power toggle (innermost button wins the
            // click; the surrounding row button still handles navigation)
            Button {
                onTogglePower?()
            } label: {
                Image(systemName: groupIcon)
                    .font(.title3)
                    .foregroundStyle(isOn ? liveColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("Turn \(isOn ? "off" : "on")")
            .accessibilityLabel("\(group.metadata.name) power")
            .accessibilityValue(isOn ? "On" : "Off")

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
                // Brightness progress bar tinted by the live light color
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(liveColor.opacity(isOn ? 0.22 : 0.08))
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
            .shadow(color: isOn ? liveColor.opacity(0.25) : .clear, radius: 8, y: 2)
        )
        .skeletonLoader(isActive: isLoading)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.snappy(duration: 0.3), value: isOn)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pressable Row Style

private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
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

    NavigationStack {
        RoomsZonesListView_macOS(
            onRoomSelected: { _ in },
            onZoneSelected: { _ in },
            onSettingsSelected: {}
        )
    }
    .environment(manager)
    .frame(width: 320, height: 480)
}
