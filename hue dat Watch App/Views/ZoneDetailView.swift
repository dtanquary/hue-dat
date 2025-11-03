//
//  ZoneDetailView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI

struct ZoneDetailView: View {
    let zoneId: String
    @ObservedObject var bridgeManager: BridgeManager

    // Power toggle state
    @State private var displayIsOn = false
    @State private var isTogglingPower = false
    @State private var hasGivenInitialPowerHaptic = false
    @State private var hasGivenFinalPowerHaptic = false

    // Brightness control state
    @State private var isSettingBrightness = false
    @State private var brightness: Double = 0
    @State private var lastBrightnessUpdate: Date = Date()
    @State private var throttleTimer: Timer?
    @State private var pendingBrightness: Double?
    @State private var isAdjustingBrightness = false
    @State private var brightnessPopoverTimer: Timer?
    @State private var hasGivenInitialBrightnessHaptic = false
    @State private var hasGivenFinalBrightnessHaptic = false
    @State private var brightnessHapticResetTimer: Timer?
    @State private var hasCompletedInitialLoad = false
    @FocusState private var isBrightnessFocused: Bool

    // Brightness optimistic state for instant UI updates
    @State private var optimisticBrightness: Double?
    @State private var previousBrightness: Double?

    // Error handling
    @State private var showBridgeUnreachableAlert = false

    // Scene picker state
    @State private var availableScenes: [HueScene] = []
    @State private var activeSceneId: String?
    @State private var showScenePicker: Bool = false
    @State private var backgroundUpdateTrigger: UUID = UUID()

    // Computed property to get live zone data
    private var zone: BridgeManager.HueZone? {
        bridgeManager.zones.first(where: { $0.id == zoneId })
    }

    private var lightStatus: Double? {
        guard let zone = zone,
              let lights = zone.groupedLights, !lights.isEmpty else {
            return optimisticBrightness
        }

        let actualBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        // Prefer optimistic state for instant UI updates
        let brightness = optimisticBrightness ?? actualBrightness

        return brightness
    }

    var body: some View {
        Group {
            if let zone = zone {
                zoneContent(for: zone)
            } else {
                VStack {
                    ProgressView()
                    Text("Loading zone...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    // If zone is not found, try to refresh zones
                    Task {
                        print("⚠️ Zone \(zoneId) not found, refreshing zones...")
                        await bridgeManager.getZones()
                    }
                }
            }
        }
        .alert("Bridge Unreachable", isPresented: $showBridgeUnreachableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Unable to connect to the Hue bridge. Please check your network connection.")
        }
    }

    @ViewBuilder
    private func zoneContent(for zone: BridgeManager.HueZone) -> some View {
        GeometryReader { outerGeometry in
            ZStack {
                // Layer 1: Single orb background with average light color
                let lights = zone.lights ?? []
                let averageColor: Color = lights.isEmpty ? .gray : bridgeManager.averageColorFromLights(lights)

                // Calculate opacity based on brightness (0-100% brightness -> 0-100% opacity)
                // Orb opacity driven directly by brightness slider value
                let orbOpacity: Double = displayIsOn ? (brightness / 100.0) : 0.0

                ColorOrbsBackground(colors: [averageColor], size: .fullscreen)
                    .opacity(orbOpacity)
                    .animation(.easeInOut(duration: 0.3), value: orbOpacity)
                    .zIndex(0)
                    .id(backgroundUpdateTrigger) // Force re-render when trigger changes

                // Layer 2: Centered ON/OFF text with limited tap area
                VStack {
                    Spacer()
                    Text(displayIsOn ? "ON" : "OFF")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(displayIsOn ? .yellow : .gray)
                        .fixedSize() // Prevent text truncation
                        .padding(20)
                        .contentShape(Circle()) // Circular tap area
                        .onTapGesture {
                            guard !isTogglingPower else { return }
                            Task {
                                await togglePower()
                            }
                        }
                        .allowsHitTesting(!isTogglingPower)
                    Spacer()
                }
                .zIndex(50)

                // Layer 3: Brightness bar on right side
                HStack {
                    Spacer()
                    brightnessBar
                        .frame(width: 30) // Fixed width for brightness bar
                }
                .zIndex(100)

                // Layer 4: Scenes button in bottom-left corner
                if !availableScenes.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                showScenePicker = true
                            }) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                            .padding(.bottom, 8)

                            Spacer()
                        }
                    }
                    .zIndex(125)
                }

                // Layer 5: Brightness percentage popover (top layer)
                if isAdjustingBrightness && brightness > 0 {
                    brightnessPopover
                        .zIndex(150)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .allowsHitTesting(false) // Popover doesn't need interaction
                }
            }
        }
        .sheet(isPresented: $showScenePicker) {
            ScenePickerView(
                scenes: availableScenes,
                activeSceneId: activeSceneId,
                onSceneSelected: { scene in
                    Task {
                        await activateScene(scene)
                    }
                },
                bridgeManager: bridgeManager
            )
        }
        .focusable()
        .focused($isBrightnessFocused)
        .digitalCrownRotation($brightness, from: 0, through: 100, by: 1, sensitivity: .low)
        .onChange(of: brightness) { oldValue, newValue in
            // Don't react to programmatic changes during initial load
            guard hasCompletedInitialLoad else { return }

            // Don't allow brightness adjustment while power is being toggled
            guard !isTogglingPower else { return }

            // If starting a new adjustment session (after previous session completed),
            // reset the final haptic flag so the user gets feedback for this new session
            if !hasGivenInitialBrightnessHaptic {
                hasGivenFinalBrightnessHaptic = false
            }

            // Give initial haptic feedback only once when user starts adjusting
            if !hasGivenInitialBrightnessHaptic {
                WKInterfaceDevice.current().play(.start)
                hasGivenInitialBrightnessHaptic = true
            }

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

            // Reset timer for haptic flag - wait longer to ensure user is done adjusting
            brightnessHapticResetTimer?.invalidate()
            brightnessHapticResetTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                // Reset flags so next adjustment session gets haptics again
                self.hasGivenInitialBrightnessHaptic = false
                self.hasGivenFinalBrightnessHaptic = false
            }

            // Throttle actual brightness update
            throttledSetBrightness(newValue)
        }
        .navigationTitle(zone.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Print detailed light information for debugging (both grouped and individual lights)
            bridgeManager.printDetailedLightInfo(for: "Zone '\(zone.metadata.name)'", groupedLights: zone.groupedLights, individualLights: zone.lights)

            // Initialize UI from cached data only (no API call)
            if let lights = zone.groupedLights, !lights.isEmpty {
                let actualOn = lights.contains { $0.on?.on == true }
                displayIsOn = actualOn

                if let lightBrightness = lights.compactMap({ $0.dimming?.brightness }).average() {
                    brightness = lightBrightness

                    // Show brightness popup on initial load (without haptic feedback)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAdjustingBrightness = true
                    }

                    // Auto-hide after 1 second
                    brightnessPopoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isAdjustingBrightness = false
                        }
                    }
                }
            }

            // Load scenes for this zone
            Task {
                availableScenes = await bridgeManager.fetchScenes(forZoneId: zoneId)

                // Detect active scene
                if let activeScene = await bridgeManager.getActiveScene(forZoneId: zoneId) {
                    activeSceneId = activeScene.id
                    print("🎬 ZoneDetailView: Active scene is '\(activeScene.metadata.name)'")
                }
            }

            // Mark initial load as complete AFTER a brief delay to ensure programmatic brightness changes don't trigger haptics
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasCompletedInitialLoad = true
            }
        }
    }

    private func togglePower() async {
        // Don't allow toggling power while brightness is being set
        guard !isSettingBrightness else { return }

        guard let zone = zone,
              let groupedLight = zone.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge else { return }

        // Store current state for rollback
        let previousState = displayIsOn

        // Give initial haptic feedback
        if !hasGivenInitialPowerHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialPowerHaptic = true
        }

        // Flip UI immediately (optimistic update)
        displayIsOn = !displayIsOn
        isTogglingPower = true

        // Send API request
        let result = await setGroupedLightAction(groupedLightId: groupedLight.id, on: displayIsOn, bridge: bridge)

        switch result {
        case .success:
            // Give success haptic
            if !hasGivenFinalPowerHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalPowerHaptic = true
            }

        case .failure(let error):
            print("❌ Toggle power failed: \(error.localizedDescription)")

            // Give failure haptic
            WKInterfaceDevice.current().play(.failure)

            // Rollback to previous state
            displayIsOn = previousState

            // Show alert that bridge was not reachable
            showBridgeUnreachableAlert = true
        }

        // Unlock UI
        isTogglingPower = false

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasGivenInitialPowerHaptic = false
            self.hasGivenFinalPowerHaptic = false
        }
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
        guard let zone = zone,
              let groupedLight = zone.groupedLights?.first,
              let bridge = bridgeManager.connectedBridge else { return }

        isSettingBrightness = true
        defer { isSettingBrightness = false }

        // Store previous states for rollback
        let previousDisplayIsOn = displayIsOn
        previousBrightness = lightStatus

        // If light is OFF, we need to turn it ON first, then set brightness
        if !displayIsOn {
            // Optimistic updates for turning on + setting brightness
            displayIsOn = true
            optimisticBrightness = value

            // Turn on the light first
            let turnOnResult = await setGroupedLightAction(groupedLightId: groupedLight.id, on: true, bridge: bridge)

            switch turnOnResult {
            case .success:
                // Now set the brightness to target value
                let setBrightnessResult = await setGroupedLightAction(groupedLightId: groupedLight.id, brightness: value, bridge: bridge)

                switch setBrightnessResult {
                case .success:
                    // Clear optimistic state
                    optimisticBrightness = nil
                    // Success haptic
                    if !hasGivenFinalBrightnessHaptic {
                        WKInterfaceDevice.current().play(.success)
                        hasGivenFinalBrightnessHaptic = true
                    }

                case .failure(let error):
                    print("❌ Set brightness failed: \(error.localizedDescription)")
                    // Revert to previous state
                    displayIsOn = previousDisplayIsOn
                    optimisticBrightness = previousBrightness
                    // Error haptic
                    WKInterfaceDevice.current().play(.failure)
                }

            case .failure(let error):
                print("❌ Turn on failed: \(error.localizedDescription)")
                // Revert to previous state
                displayIsOn = previousDisplayIsOn
                optimisticBrightness = previousBrightness
                // Error haptic
                WKInterfaceDevice.current().play(.failure)
            }
        } else {
            // Light is already ON, just set brightness
            // Optimistic update
            optimisticBrightness = value

            let result = await setGroupedLightAction(groupedLightId: groupedLight.id, brightness: value, bridge: bridge)

            switch result {
            case .success:
                // Clear optimistic state
                optimisticBrightness = nil
                // Success haptic
                if !hasGivenFinalBrightnessHaptic {
                    WKInterfaceDevice.current().play(.success)
                    hasGivenFinalBrightnessHaptic = true
                }

            case .failure(let error):
                print("❌ Set brightness failed: \(error.localizedDescription)")
                // Revert to previous brightness
                optimisticBrightness = previousBrightness
                // Error haptic
                WKInterfaceDevice.current().play(.failure)
            }
        }

        // Clear previous state
        previousBrightness = nil
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
                        .fill(displayIsOn ? Color.yellow : Color.gray.opacity(0.5))
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

    // MARK: - Scene Actions

    private func activateScene(_ scene: HueScene) async {
        print("🎬 Activating scene: \(scene.metadata.name)")

        let result = await bridgeManager.activateScene(scene.id)

        switch result {
        case .success:
            print("✅ Scene activated: \(scene.metadata.name)")
            activeSceneId = scene.id

        case .failure(let error):
            print("❌ Failed to activate scene: \(error.localizedDescription)")
            showBridgeUnreachableAlert = true
        }
    }

    // MARK: - Actions

    private func setGroupedLightAction(groupedLightId: String, on: Bool? = nil, brightness: Double? = nil, bridge: BridgeConnectionInfo) async -> Result<Void, Error> {
        let urlString = "https://\(bridge.bridge.internalipaddress)/clip/v2/resource/grouped_light/\(groupedLightId)"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "ZoneDetailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }

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

            // Parse response to check for errors
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               !errors.isEmpty {
                let errorDesc = errors.first?["description"] as? String ?? "Unknown error"
                return .failure(NSError(domain: "HueBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: errorDesc]))
            }

            return .success(())
        } catch {
            print("Failed to set light action: \(error)")
            return .failure(error)
        }
    }
}
