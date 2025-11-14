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

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and buttons
            HStack {
                Text("Rooms & Zones")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if let timestamp = bridgeManager.lastRefreshTimestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // SSE status indicator
                SSEStatusIndicator()
                    .environmentObject(bridgeManager)

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
                }
                .buttonStyle(.borderless)
                .disabled(bridgeManager.isRefreshing || isTurningOffAll)
                .help("Turn Off All Lights")

                Button(action: {
                    Task {
                        await bridgeManager.refreshAllData()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(bridgeManager.isRefreshing)
                .help("Refresh")

                Button(action: onSettingsSelected) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .help("Settings")
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
            Circle()
                .fill(isOn ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
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
        default: return "lightbulb"
        }
    }
}

// MARK: - Zone Row View

struct ZoneRowView: View {
    let zone: HueZone

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
            Circle()
                .fill(isOn ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    RoomsZonesListView_macOS(
        onRoomSelected: { _ in },
        onZoneSelected: { _ in },
        onSettingsSelected: {}
    )
    .environmentObject(BridgeManager())
}
