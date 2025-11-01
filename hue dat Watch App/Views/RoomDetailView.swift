//
//  RoomDetailView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI

struct RoomDetailView: View {
    let roomId: String
    @ObservedObject var bridgeManager: BridgeManager
    @Binding var activeDetailId: String?
    @Binding var activeDetailType: ActiveDetailType?

    @State private var isTogglingPower = false
    @State private var brightness: Double = 0
    @State private var lastBrightnessUpdate: Date = Date()
    @State private var throttleTimer: Timer?
    @State private var pendingBrightness: Double?
    @State private var refreshTask: Task<Void, Never>?
    @State private var isAdjustingBrightness = false
    @State private var brightnessPopoverTimer: Timer?
    @FocusState private var isBrightnessFocused: Bool

    // Computed property to get live room data
    private var room: BridgeManager.HueRoom? {
        bridgeManager.rooms.first(where: { $0.id == roomId })
    }

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let room = room,
              let lights = room.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        Group {
            if let room = room {
                roomContent(for: room)
            } else {
                VStack {
                    ProgressView()
                    Text("Loading room...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            // Notify ContentView that we're viewing this room
            activeDetailId = roomId
            activeDetailType = .room
            print("📍 Entered room detail view: \(roomId)")
        }
        .onDisappear {
            // Clear active detail when leaving
            activeDetailId = nil
            activeDetailType = nil
            print("📍 Left room detail view")
        }
    }

    @ViewBuilder
    private func roomContent(for room: BridgeManager.HueRoom) -> some View {
        ZStack {
            // Background brightness bar on right side
            brightnessBar

            // Brightness percentage popover (left of bar top)
            if isAdjustingBrightness && brightness > 0 {
                brightnessPopover
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Centered ON/OFF text
            Text(lightStatus.isOn ? "ON" : "OFF")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(lightStatus.isOn ? .yellow : .gray)
                .opacity(isTogglingPower ? 0.3 : 1.0)
                .animation(isTogglingPower ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isTogglingPower)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isTogglingPower else { return }
            Task {
                await togglePower()
            }
        }
        .focusable()
        .focused($isBrightnessFocused)
        .digitalCrownRotation($brightness, from: 0, through: 100, by: 1, sensitivity: .low)
        .onChange(of: brightness) { oldValue, newValue in
            // Show popover with animation
            withAnimation(.easeInOut(duration: 0.2)) {
                isAdjustingBrightness = true
            }

            // Reset timer for hiding popover
            brightnessPopoverTimer?.invalidate()
            brightnessPopoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAdjustingBrightness = false
                }
            }

            // Throttle actual brightness update
            throttledSetBrightness(newValue)
        }
        .navigationTitle(room.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let lightBrightness = lightStatus.brightness {
                brightness = lightBrightness
            }
        }
    }

    private func togglePower() async {
        guard let room = room,
              let groupedLight = room.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge else { return }

        isTogglingPower = true
        defer { isTogglingPower = false }

        let newState = !(groupedLight.on?.on ?? false)
        await setGroupedLightAction(groupedLightId: groupedLight.id, on: newState, bridge: bridge)
        debouncedRefreshRoom()
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
        guard let room = room,
              let groupedLight = room.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge,
              lightStatus.isOn else { return }

        await setGroupedLightAction(groupedLightId: groupedLight.id, brightness: value, bridge: bridge)
        debouncedRefreshRoom()
    }

    private func debouncedRefreshRoom() {
        // Cancel any existing refresh task
        refreshTask?.cancel()

        // Create new task that waits 400ms before refreshing
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Refresh just this room
            await bridgeManager.refreshRoom(roomId: roomId)
        }
    }

    // MARK: - View Components

    private var brightnessBar: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()

                ZStack(alignment: .bottom) {
                    // Empty bar background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 8)

                    // Filled portion based on brightness
                    RoundedRectangle(cornerRadius: 4)
                        .fill(lightStatus.isOn ? Color.yellow : Color.gray.opacity(0.5))
                        .frame(width: 8, height: geometry.size.height * CGFloat(brightness / 100))
                }
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Calculate brightness based on Y position
                            // Y=0 is top (100% brightness), Y=height is bottom (0% brightness)
                            let yPosition = value.location.y
                            let barHeight = geometry.size.height
                            let newBrightness = max(0, min(100, 100 - (yPosition / barHeight * 100)))

                            brightness = newBrightness
                        }
                )
            }
        }
    }

    private var brightnessPopover: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                Text("\(Int(brightness))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                    .offset(
                        x: -20,
                        y: geometry.size.height * CGFloat(1 - brightness / 100) - 12
                    )
            }
        }
    }

    // MARK: - Actions

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
