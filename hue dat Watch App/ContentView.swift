//
//  ContentView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var discoveryService = BridgeDiscoveryService()
    @StateObject private var bridgeManager = BridgeManager()
    @State private var showBridgesList = false
    @State private var showDisconnectAlert = false
    @State private var showConnectionValidationAlert = false
    @State private var connectionValidationErrorMessage = ""
    @State private var refreshTimer: Timer?
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Main content
                    if let connectedBridge = bridgeManager.connectedBridge {
                        // Connected state
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Text(connectedBridge.bridge.displayName)
                                    .font(.headline)
                                
                                Text(connectedBridge.bridge.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("Connected \(connectedBridge.connectedDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                            
                            // Zones and Rooms with Light Status
                            if !bridgeManager.rooms.isEmpty || !bridgeManager.zones.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Lights & Groups")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        Button {
                                            Task {
                                                await bridgeManager.getRooms()
                                                await bridgeManager.getZones()
                                            }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Refresh light status")
                                    }
                                    
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Show Rooms
                                            if !bridgeManager.rooms.isEmpty {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Rooms")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)
                                                    
                                                    ForEach(bridgeManager.rooms) { room in
                                                        RoomZoneItemView(
                                                            name: room.metadata.name,
                                                            type: "Room",
                                                            archetype: room.metadata.archetype,
                                                            groupedLights: room.groupedLights
                                                        )
                                                    }
                                                }
                                            }
                                            
                                            // Show Zones
                                            if !bridgeManager.zones.isEmpty {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Zones")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)
                                                    
                                                    ForEach(bridgeManager.zones) { zone in
                                                        RoomZoneItemView(
                                                            name: zone.metadata.name,
                                                            type: "Zone",
                                                            archetype: zone.metadata.archetype,
                                                            groupedLights: zone.groupedLights
                                                        )
                                                    }
                                                }
                                            }
                                            
                                            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                                                Text("No rooms or zones found")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 300)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.regularMaterial)
                                        .opacity(0.8)
                                )
                            }
                            
                            Button("Disconnect", role: .destructive) {
                                showDisconnectAlert = true
                            }
                            .accessibilityLabel("Disconnect from current bridge")
                            .glassEffect()
                        }
                    } else {
                        // Discovery state
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await discoveryService.discoverBridges()
                                    if !discoveryService.discoveredBridges.isEmpty {
                                        showBridgesList = true
                                    }
                                }
                            } label: {
                                HStack {
                                    if discoveryService.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    Text(discoveryService.isLoading ? "Searching..." : "Find Bridges")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .disabled(discoveryService.isLoading)
                            .accessibilityLabel("Discover Hue bridges on network")
                            .glassEffect()
                            
                            // Tappable bridge count
                            if !discoveryService.discoveredBridges.isEmpty && !discoveryService.isLoading {
                                Button {
                                    showBridgesList = true
                                } label: {
                                    Text("\(discoveryService.discoveredBridges.count) found")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show \(discoveryService.discoveredBridges.count) discovered bridge\(discoveryService.discoveredBridges.count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Hue Control")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // When the view appears (app launch or wake), validate any restored connection
                if bridgeManager.connectedBridge != nil {
                    Task {
                        await bridgeManager.validateConnection()
                    }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                // When the scene becomes active again, re-validate the connection
                if newPhase == .active, bridgeManager.connectedBridge != nil {
                    Task {
                        await bridgeManager.validateConnection()
                    }
                    // Start periodic refresh timer when active
                    startRefreshTimer()
                } else {
                    // Stop timer when inactive
                    stopRefreshTimer()
                }
            }
        }
        .sheet(isPresented: $showBridgesList, onDismiss: {
            // Cancel any ongoing discovery when sheet is dismissed
            if discoveryService.isLoading {
                discoveryService.cancelDiscovery()
            }
        }) {
            BridgesListView(bridges: discoveryService.discoveredBridges, bridgeManager: bridgeManager)
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
                stopRefreshTimer()
            }
        } message: {
            Text("Are you sure you want to disconnect? You'll need to set up the connection again.")
        }
        .alert("Connection Validation Failed", isPresented: $showConnectionValidationAlert) {
            Button("OK") { }
            Button("Reconnect") {
                showBridgesList = true
                Task {
                    await discoveryService.discoverBridges()
                }
            }
        } message: {
            Text("Bridge connection validation failed: \(connectionValidationErrorMessage)")
        }
        .alert("Discovery Error", isPresented: Binding(
            get: { discoveryService.error != nil },
            set: { if !$0 { discoveryService.error = nil } }
        )) {
            Button("OK") {
                discoveryService.error = nil
            }
        } message: {
            if let error = discoveryService.error {
                Text("Failed to discover bridges: \(error.localizedDescription)")
            }
        }
        .alert("No Bridges Found", isPresented: $discoveryService.showNoBridgesAlert) {
            Button("OK") { }
        } message: {
            Text("No Hue bridges could be found on your network. Make sure your bridge is connected and try again.")
        }
        .onReceive(bridgeManager.connectionValidationPublisher) { result in
            switch result {
            case .success:
                print("✅ ContentView: Bridge connection validation succeeded")
                Task {
                    await bridgeManager.getRooms()
                }
                Task {
                    await bridgeManager.getZones()
                }
                // Start refresh timer once we have a successful connection
                if scenePhase == .active {
                    startRefreshTimer()
                }
            case .failure(let message):
                print("❌ ContentView: Bridge connection validation failed: \(message)")
                connectionValidationErrorMessage = message
                showConnectionValidationAlert = true
                stopRefreshTimer()
            }
        }
    }
    
    // MARK: - Timer Functions
    private func startRefreshTimer() {
        stopRefreshTimer() // Stop any existing timer first
        
        guard bridgeManager.connectedBridge != nil else { return }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                await bridgeManager.getRooms()
                await bridgeManager.getZones()
            }
        }
        print("🔄 Started refresh timer (5 second interval)")
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("⏹️ Stopped refresh timer")
    }
}

// MARK: - Room/Zone Item View
struct RoomZoneItemView: View {
    let name: String
    let type: String
    let archetype: String
    let groupedLights: [BridgeManager.HueGroupedLight]?
    
    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = groupedLights, !lights.isEmpty else {
            return (false, nil)
        }
        
        // Aggregate status from all grouped lights
        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()
        
        return (anyOn, averageBrightness)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(type.lowercased())
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                        .foregroundStyle(.secondary)
                }
                
                Text(archetype.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Light status indicator
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(lightStatus.isOn ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(lightStatus.isOn ? "ON" : "OFF")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(lightStatus.isOn ? Color.green : Color.gray)
                }
                
                if let brightness = lightStatus.brightness {
                    Text("\(Int(brightness))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if let groupedLights = groupedLights {
                    Text("\(groupedLights.count) light\(groupedLights.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Debug Light Group View (kept for detailed debugging)
struct DebugLightGroupView: View {
    let name: String
    let type: String
    let groupedLight: BridgeManager.HueGroupedLight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(type): \(name)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Text("ID: \(String(groupedLight.id.prefix(8)))...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // On/Off Status
                HStack {
                    Text("\"on\":")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("{ \"on\": \(groupedLight.on?.on ?? false) }")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(groupedLight.on?.on ?? false ? Color.green : Color.red)
                }
                
                // Dimming/Brightness Status
                if let dimming = groupedLight.dimming {
                    HStack {
                        Text("\"dimming\":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("{ \"brightness\": \(String(format: "%.2f", dimming.brightness)) }")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.blue)
                    }
                } else {
                    HStack {
                        Text("\"dimming\":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("null")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Color Temperature (if available)
                if let colorTemp = groupedLight.color_temperature {
                    HStack {
                        Text("\"color_temp\":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let mirek = colorTemp.mirek {
                            Text("{ \"mirek\": \(mirek) }")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.orange)
                        } else {
                            Text("null")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Color XY (if available)
                if let color = groupedLight.color, let xy = color.xy {
                    HStack {
                        Text("\"color\":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("{ \"x\": \(String(format: "%.3f", xy.x)), \"y\": \(String(format: "%.3f", xy.y)) }")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.purple)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Array Extension for Average Calculation
extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

#Preview {
    ContentView()
}
