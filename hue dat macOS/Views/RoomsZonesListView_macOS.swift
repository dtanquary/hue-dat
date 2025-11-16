//
//  RoomsZonesListView_macOS.swift
//  hue dat macOS
//
//  List of rooms and zones for macOS with native controls
//

import SwiftUI
import HueDatShared

struct RoomsZonesListView_macOS: View {
    @EnvironmentObject var bridgeManager: BridgeManager

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
        VStack(spacing: 0) {
            // Header with title and buttons
            HStack {
                Text("")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                /*
                if let timestamp = bridgeManager.lastRefreshTimestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                 */

                // SSE status indicator
                SSEStatusIndicator()
                    .environmentObject(bridgeManager)
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
                            RoundedRectangle(cornerRadius: 6)
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
                        await bridgeManager.refreshAllData()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: bridgeManager.isRefreshing)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
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
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(isSettingsHovered ? 0.1 : 0))
                        )
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .onHover { isSettingsHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: isSettingsHovered)
            }
            .padding()

            Divider()

            // Content
            if bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones {
                loadingView
            } else if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                emptyView
            } else {
                listContent
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
            ProgressView()
            Text("Loading rooms and zones...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Rooms or Zones")
                .font(.title3)
                .fontWeight(.semibold)

            Button("Refresh") {
                Task {
                    await bridgeManager.refreshAllData()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Rooms Section
                if !bridgeManager.rooms.isEmpty {
                    sectionHeader("Rooms", count: bridgeManager.rooms.count)

                    ForEach(bridgeManager.rooms) { room in
                        RoomRowView(room: room)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onRoomSelected(room)
                            }
                    }
                }

                // Zones Section
                if !bridgeManager.zones.isEmpty {
                    sectionHeader("Zones", count: bridgeManager.zones.count)
                        .padding(.top, bridgeManager.rooms.isEmpty ? 0 : 8)

                    ForEach(bridgeManager.zones) { zone in
                        ZoneRowView(zone: zone)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onZoneSelected(zone)
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
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Room Row View

struct RoomRowView: View {
    let room: HueRoom
    @State private var isHovered: Bool = false

    private var groupedLight: HueGroupedLight? {
        room.groupedLights?.first
    }

    private var isOn: Bool {
        groupedLight?.on?.on ?? false
    }

    private var brightness: Double? {
        groupedLight?.dimming?.brightness
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconForArchetype(room.metadata.archetype))
                .font(.title3)
                .foregroundStyle(isOn ? .yellow : .secondary)
                .frame(width: 24)

            // Name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(room.metadata.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let brightness = brightness {
                    Text("\(Int(brightness))% brightness")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func iconForArchetype(_ archetype: String) -> String {
        switch archetype.lowercased() {
        case "living_room": return "sofa"
        case "bedroom": return "bed.double"
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower"
        case "office": return "desktopcomputer"
        case "dining": return "fork.knife"
        case "hallway": return "figure.walk"
        case "garage": return "car"
        default: return "lightbulb.led.fill"
        }
    }
}

// MARK: - Zone Row View

struct ZoneRowView: View {
    let zone: HueZone
    @State private var isHovered: Bool = false

    private var groupedLight: HueGroupedLight? {
        zone.groupedLights?.first
    }

    private var isOn: Bool {
        groupedLight?.on?.on ?? false
    }

    private var brightness: Double? {
        groupedLight?.dimming?.brightness
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(isOn ? .yellow : .secondary)
                .frame(width: 24)

            // Name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.metadata.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let brightness = brightness {
                    Text("\(Int(brightness))% brightness")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

#Preview("With Sample Data") {
    @Previewable @StateObject var manager: BridgeManager = {
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
                    color_temperature: nil,
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
                    color_temperature: nil,
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
    .environmentObject(manager)
    .frame(width: 320, height: 480)
}
