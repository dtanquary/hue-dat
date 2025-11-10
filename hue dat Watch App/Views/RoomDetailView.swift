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


    // Scene picker state
    @State private var availableScenes: [HueScene] = []
    @State private var activeSceneId: String?
    @State private var showScenePicker: Bool = false
    @State private var backgroundUpdateTrigger: UUID = UUID()
    @State private var optimisticSceneColors: [Color]? = nil  // For instant orb updates when scene selected

    // Computed property to get live room data
    private var room: BridgeManager.HueRoom? {
        bridgeManager.rooms.first(where: { $0.id == roomId })
    }

    private var lightStatus: Double? {
        guard let room = room,
              let lights = room.groupedLights, !lights.isEmpty else {
            return optimisticBrightness
        }

        let actualBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        // Prefer optimistic state for instant UI updates
        let brightness = optimisticBrightness ?? actualBrightness

        return brightness
    }

    // Computed property for orb opacity (0.0 to 1.0)
    private var orbOpacity: Double {
        displayIsOn ? (brightness / 100.0) : 0.0
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
    }

    @ViewBuilder
    private func roomContent(for room: BridgeManager.HueRoom) -> some View {
        GeometryReader { outerGeometry in
            ZStack {
                // Layer 1: Brightness-controlled orange/grey orb background
                let groupedLight = room.groupedLights?.first
                let isOn = groupedLight?.on?.on ?? false
                let currentBrightness = groupedLight?.dimming?.brightness ?? 0.0

                ColorOrbsBackground(brightness: currentBrightness, isOn: isOn)
                    .opacity(orbOpacity)
                    .animation(.easeInOut(duration: 0.3), value: orbOpacity)
                    .zIndex(0)
                    .id(backgroundUpdateTrigger) // Force re-render when trigger changes

                // Layer 2: Centered power icon with limited tap area
                VStack {
                    Spacer()
                    Image(systemName: "power")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(displayIsOn ? .yellow : .gray)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .fixedSize() // Prevent icon truncation
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
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .background(Color.clear)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .glassEffect()

                            Spacer()
                        }
                    }
                    .zIndex(125)
                    .offset(x: 16, y: 0)
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
        .navigationTitle(room.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize UI from cached data only (no API call)
            if let lights = room.groupedLights, !lights.isEmpty {
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

            // Load individual lights for color orb (if not already loaded)
            // and load scenes for this room
            Task {
                // Fetch scenes
                availableScenes = await bridgeManager.fetchScenes(forRoomId: roomId)

                // Detect active scene
                if let activeScene = await bridgeManager.getActiveScene(forRoomId: roomId) {
                    activeSceneId = activeScene.id
                    print("🎬 RoomDetailView: Active scene is '\(activeScene.metadata.name)'")

                    // Restore scene colors if a scene is active (persist across navigation)
                    let sceneColors = bridgeManager.extractColorsFromScene(activeScene)
                    if !sceneColors.isEmpty {
                        optimisticSceneColors = sceneColors
                        print("🎨 RoomDetailView: Restored scene colors for '\(activeScene.metadata.name)'")
                    }
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

        guard let room = room,
              let groupedLight = room.groupedLights?.first else { return }

        // Give initial haptic feedback
        if !hasGivenInitialPowerHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialPowerHaptic = true
        }

        // Flip UI immediately (optimistic update)
        displayIsOn = !displayIsOn
        isTogglingPower = true

        // Clear scene colors since user is manually controlling the lights
        optimisticSceneColors = nil

        // Send API request - assume success
        _ = await bridgeManager.setGroupedLightPower(id: groupedLight.id, on: displayIsOn)

        // If we just turned ON the light, fetch the current brightness from the bridge
        if displayIsOn {
            if let updatedGroupedLight = await bridgeManager.fetchGroupedLight(groupedLightId: groupedLight.id) {
                if let currentBrightness = updatedGroupedLight.dimming?.brightness {
                    print("🔄 Fetched brightness after power on: \(Int(currentBrightness))%")
                    // Update brightness with animation to ensure orb opacity updates smoothly
                    withAnimation(.easeInOut(duration: 0.3)) {
                        brightness = currentBrightness
                    }
                    bridgeManager.updateLocalRoomState(roomId: roomId, on: displayIsOn, brightness: currentBrightness)
                } else {
                    bridgeManager.updateLocalRoomState(roomId: roomId, on: displayIsOn)
                }
            } else {
                // Fetch failed, just update on state
                bridgeManager.updateLocalRoomState(roomId: roomId, on: displayIsOn)
            }
        } else {
            // Light was turned OFF, just update the on state
            bridgeManager.updateLocalRoomState(roomId: roomId, on: displayIsOn)
        }

        // Give success haptic
        if !hasGivenFinalPowerHaptic {
            WKInterfaceDevice.current().play(.success)
            hasGivenFinalPowerHaptic = true
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
        // Throttling is now handled by BridgeManager.sendGroupedLightCommand()
        // Simply call setBrightness - no need for view-level throttling
        Task {
            await setBrightness(value)
        }
    }

    private func setBrightness(_ value: Double) async {
        guard let room = room,
              let groupedLight = room.groupedLights?.first else { return }

        isSettingBrightness = true
        defer { isSettingBrightness = false }

        // Clear scene colors since user is manually controlling the lights
        optimisticSceneColors = nil

        // If light is OFF, we need to turn it ON first with the target brightness
        if !displayIsOn {
            // Optimistic updates for turning on + setting brightness
            displayIsOn = true
            optimisticBrightness = value

            // Use combined method - assume success
            _ = await bridgeManager.setGroupedLightPowerAndBrightness(id: groupedLight.id, on: true, brightness: value)

            // Update local state in BridgeManager so list view reflects the change
            bridgeManager.updateLocalRoomState(roomId: roomId, on: true, brightness: value)

            // Clear optimistic state
            optimisticBrightness = nil
            // Success haptic
            if !hasGivenFinalBrightnessHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalBrightnessHaptic = true
            }
        } else {
            // Light is already ON, just set brightness
            // Optimistic update
            optimisticBrightness = value

            _ = await bridgeManager.setGroupedLightBrightness(id: groupedLight.id, brightness: value)

            // Update local state in BridgeManager so list view reflects the change
            bridgeManager.updateLocalRoomState(roomId: roomId, brightness: value)

            // Clear optimistic state
            optimisticBrightness = nil
            // Success haptic
            if !hasGivenFinalBrightnessHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalBrightnessHaptic = true
            }
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

        // Update orb colors immediately using scene data (no need to wait for network)
        let sceneColors = bridgeManager.extractColorsFromScene(scene)
        if !sceneColors.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                optimisticSceneColors = sceneColors
            }
        }

        let result = await bridgeManager.activateScene(scene.id)

        switch result {
        case .success:
            print("✅ Scene activated: \(scene.metadata.name)")
            activeSceneId = scene.id
            // Keep using scene colors - no need to revert to light data
            // The scene colors ARE the correct colors for this scene

        case .failure(let error):
            print("❌ Failed to activate scene: \(error.localizedDescription)")
            // Scene activation failed, continue without showing error
        }
    }

    // MARK: - Actions
    // Note: Light control actions now use centralized BridgeManager methods
    // (setGroupedLightPower, setGroupedLightBrightness, setGroupedLightPowerAndBrightness)
    // which provide automatic rate limiting (1 command/sec for grouped lights)

}
