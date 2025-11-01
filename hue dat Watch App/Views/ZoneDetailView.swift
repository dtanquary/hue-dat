//
//  ZoneDetailView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI

struct ZoneDetailView: View {
    let zone: BridgeManager.HueZone
    @ObservedObject var bridgeManager: BridgeManager

    @State private var isTogglingPower = false
    @State private var brightness: Double = 0
    @State private var lastBrightnessUpdate: Date = Date()
    @State private var throttleTimer: Timer?
    @State private var pendingBrightness: Double?
    @FocusState private var isBrightnessFocused: Bool

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = zone.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 50))
                        .foregroundStyle(lightStatus.isOn ? .yellow : .secondary)

                    Text(zone.metadata.name)
                        .font(.title3)

                    Text(zone.metadata.archetype.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let groupedLights = zone.groupedLights {
                        Text("\(groupedLights.count) light\(groupedLights.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top)

                // Controls
                VStack(spacing: 16) {
                    // Power toggle
                    Button {
                        Task {
                            await togglePower()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "power")
                            Text(lightStatus.isOn ? "Turn Off" : "Turn On")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .disabled(isTogglingPower)
                    .glassEffect()

                    // Brightness slider (only show when on)
                    if lightStatus.isOn {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Brightness")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(brightness))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: $brightness, in: 0...100, step: 1)
                                .onChange(of: brightness) { oldValue, newValue in
                                    throttledSetBrightness(newValue)
                                }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                        )
                        .focusable()
                        .focused($isBrightnessFocused)
                        .digitalCrownRotation($brightness, from: 0, through: 100, by: 1, sensitivity: .low)
                    }
                }
                .padding(.horizontal)

                // Status info
                if let groupedLights = zone.groupedLights, !groupedLights.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(groupedLights) { light in
                            LightStatusCard(light: light)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(zone.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let lightBrightness = lightStatus.brightness {
                brightness = lightBrightness
            }
        }
    }

    private func togglePower() async {
        guard let groupedLight = zone.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge else { return }

        isTogglingPower = true
        defer { isTogglingPower = false }

        let newState = !(groupedLight.on?.on ?? false)
        await setGroupedLightAction(groupedLightId: groupedLight.id, on: newState, bridge: bridge)
        await bridgeManager.getZones()
    }

    private func throttledSetBrightness(_ value: Double) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastBrightnessUpdate)
        let throttleInterval: TimeInterval = 0.3 // 300ms throttle
        
        if timeSinceLastUpdate >= throttleInterval {
            // Enough time has passed, apply immediately
            lastBrightnessUpdate = now
            Task {
                await setBrightness(value)
            }
        } else {
            // Too soon, schedule for later
            pendingBrightness = value
            throttleTimer?.invalidate()
            
            let remainingTime = throttleInterval - timeSinceLastUpdate
            throttleTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { _ in
                if let pending = self.pendingBrightness {
                    self.lastBrightnessUpdate = Date()
                    self.pendingBrightness = nil
                    Task {
                        await self.setBrightness(pending)
                    }
                }
            }
        }
    }

    private func setBrightness(_ value: Double) async {
        guard let groupedLight = zone.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge,
              lightStatus.isOn else { return }

        await setGroupedLightAction(groupedLightId: groupedLight.id, brightness: value, bridge: bridge)
    }

    private func setGroupedLightAction(groupedLightId: String, on: Bool? = nil, brightness: Double? = nil, bridge: BridgeConnectionInfo) async {
        let urlString = "https://\(bridge.bridge.internalipaddress)/clip/v2/resource/grouped_light/\(groupedLightId)"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(bridge.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [:]
        if let on = on {
            payload["on"] = ["on": on]
        }
        if let brightness = brightness {
            payload["dimming"] = ["brightness": brightness]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)

            if let responseString = String(data: data, encoding: .utf8) {
                print("Action response: \(responseString)")
            }
        } catch {
            print("Failed to set light action: \(error)")
        }
    }
}
