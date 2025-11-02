//
//  RoomsAndZonesListView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI

struct RoomsAndZonesListView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var isRefreshing = false
    @State private var hasLoadedData = false
    @State private var rotationAngle: Double = 0
    @State private var showSettings = false

    var body: some View {
        Group {
            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty && !isRefreshing && hasLoadedData {
                VStack(spacing: 12) {
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
                }
            }
        }
        .navigationTitle("Rooms & Zones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await refreshData()
                    }
                } label: {
                    Image(systemName: isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        .rotationEffect(.degrees(rotationAngle))
                }
                .disabled(isRefreshing)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(bridgeManager: bridgeManager)
        }
        .onChange(of: isRefreshing) { _, newValue in
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

                    VStack(spacing: 12) {
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
            await refreshData()
        }
    }

    private func refreshData() async {
        isRefreshing = true
        await bridgeManager.getRooms()
        await bridgeManager.getZones()
        isRefreshing = false
        hasLoadedData = true
    }
}

// MARK: - Room Row View
struct RoomRowView: View {
    let room: BridgeManager.HueRoom

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = room.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForArchetype(room.metadata.archetype))
                .font(.title3)
                .foregroundStyle(lightStatus.isOn ? .yellow : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(room.metadata.name)
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(lightStatus.isOn ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(lightStatus.isOn ? .primary : .secondary)

                if let brightness = lightStatus.brightness {
                    Text("\(Int(brightness))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
        default: return "lightbulb.group"
        }
    }
}

// MARK: - Zone Row View
struct ZoneRowView: View {
    let zone: BridgeManager.HueZone

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = zone.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .foregroundStyle(lightStatus.isOn ? .yellow : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.metadata.name)
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(lightStatus.isOn ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(lightStatus.isOn ? .primary : .secondary)

                if let brightness = lightStatus.brightness {
                    Text("\(Int(brightness))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
