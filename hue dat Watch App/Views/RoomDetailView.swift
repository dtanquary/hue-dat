//
//  RoomDetailView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI
import HueDatShared

struct RoomDetailView: View {
    let roomId: String
    @ObservedObject var bridgeManager: BridgeManager

    // Tunable parameter for crown brightness adjustment sensitivity
    private let crownBrightnessDeltaMultiplier: Double = 1.0

    // Power toggle state
    @State private var displayIsOn = false
    @State private var isTogglingPower = false
    @State private var hasGivenInitialPowerHaptic = false
    @State private var hasGivenFinalPowerHaptic = false

    // Brightness control state
    @State private var isSettingBrightness = false
    @State private var brightness: Double = 0
    @State private var brightnessThrottleTimer: Timer?
    @State private var isAdjustingBrightness = false
    @State private var brightnessPopoverTimer: Timer?
    @State private var hasGivenInitialBrightnessHaptic = false
    @State private var hasGivenFinalBrightnessHaptic = false
    @State private var brightnessHapticResetTimer: Timer?
    @State private var hasCompletedInitialLoad = false
    @FocusState private var isBrightnessFocused: Bool

    // Throttle state for crown adjustment
    @State private var lastBrightnessValue: Double = 0
    @State private var accumulatedDelta: Double = 0
    @State private var canSendBrightnessUpdate: Bool = true

    // Brightness optimistic state for instant UI updates
    @State private var optimisticBrightness: Double?
    @State private var previousBrightness: Double?


    // Scene picker state
    @State private var availableScenes: [HueScene] = []
    @State private var activeSceneId: String?
    @State private var showScenePicker: Bool = false
    @State private var backgroundUpdateTrigger: UUID = UUID()
    @State private var optimisticSceneColors: [Color]? = nil  // For instant orb updates when scene selected
    @State private var hasFetchedScenes: Bool = false  // Guard to prevent duplicate fetchScenes calls
    @State private var isApplyingScene: Bool = false  // Guard to prevent onChange from firing during scene activation

    // Computed property to get live room data
    private var room: HueRoom? {
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
    private func roomContent(for room: HueRoom) -> some View {
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
                    Button {
                        guard !isTogglingPower else { return }
                        Task {
                            await togglePower()
                        }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(displayIsOn ? .yellow : .gray)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .fixedSize() // Prevent icon truncation
                            .padding(20)
                            .contentShape(Circle()) // Circular tap area
                    }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction, isEnabled: !isTogglingPower)
                    .allowsHitTesting(!isTogglingPower)
                    .onLongPressGesture(minimumDuration: 1.0) {
                        guard !isTogglingPower else { return }
                        Task {
                            await turnOff()
                        }
                    }
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
                            .buttonStyle(.borderless)
                            .padding(8)
                            .glassEffect()

                            Spacer()
                        }
                    }
                    .zIndex(125)
                    .offset(x: 16, y: 16)
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
            guard hasCompletedInitialLoad else {
                lastBrightnessValue = newValue
                return
            }

            // Don't allow brightness adjustment while power is being toggled
            guard !isTogglingPower else { return }

            // Don't trigger API call when applying scene brightness
            guard !isApplyingScene else {
                lastBrightnessValue = newValue
                return
            }

            // Calculate delta from previous value
            let delta = newValue - lastBrightnessValue
            lastBrightnessValue = newValue

            // Accumulate the delta
            accumulatedDelta += delta

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

            // Throttle brightness updates - send immediately if gate is open, otherwise accumulate
            if canSendBrightnessUpdate {
                // Send the API call immediately
                let deltaToSend = accumulatedDelta
                accumulatedDelta = 0  // Reset accumulator
                canSendBrightnessUpdate = false  // Close the gate

                Task {
                    await adjustBrightnessWithThrottle(delta: deltaToSend)
                }

                // Open the gate after throttle period
                brightnessThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    self.canSendBrightnessUpdate = true

                    // If there's accumulated delta, send it now
                    if self.accumulatedDelta != 0 {
                        let deltaToSend = self.accumulatedDelta
                        self.accumulatedDelta = 0
                        self.canSendBrightnessUpdate = false

                        Task {
                            await self.adjustBrightnessWithThrottle(delta: deltaToSend)
                        }

                        // Schedule another timer to re-open the gate
                        self.brightnessThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            self.canSendBrightnessUpdate = true
                        }
                    }
                }
            }
            // If gate is closed, delta is already accumulated above, just wait for timer
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
                    lastBrightnessValue = lightBrightness  // Initialize for delta tracking

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

            // Load scenes for this room (guard against duplicate calls)
            Task {
                guard !hasFetchedScenes else {
                    print("⏭️ RoomDetailView: Skipping duplicate fetchScenes call")
                    return
                }
                hasFetchedScenes = true

                // Fetch scenes
                availableScenes = await bridgeManager.fetchScenes(forRoomId: roomId)
            }

            // Mark initial load as complete AFTER a brief delay to ensure programmatic brightness changes don't trigger haptics
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasCompletedInitialLoad = true
            }
        }
    }

    private func togglePower() async {
        print("🔘 togglePower() called - displayIsOn: \(displayIsOn), isTogglingPower: \(isTogglingPower), isSettingBrightness: \(isSettingBrightness)")

        // Don't allow toggling power while brightness is being set
        guard !isSettingBrightness else {
            print("❌ togglePower blocked: brightness is being set")
            return
        }

        guard let currentRoom = room,
              let groupedLight = currentRoom.groupedLights?.first else {
            print("❌ togglePower blocked: room=\(room != nil), groupedLights=\(room?.groupedLights != nil), count=\(room?.groupedLights?.count ?? 0)")
            return
        }

        print("✅ togglePower proceeding with groupedLight.id=\(groupedLight.id)")

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

        // Send API request directly to HueAPIService - only revert on network failure
        do {
            try await HueAPIService.shared.setPower(groupedLightId: groupedLight.id, on: displayIsOn)
            print("✅ Power toggle succeeded: \(displayIsOn ? "ON" : "OFF")")

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
        } catch {
            // Network failure - revert UI state
            print("❌ Power toggle failed: \(error.localizedDescription)")
            displayIsOn = !displayIsOn  // Revert to previous state
            WKInterfaceDevice.current().play(.failure)
        }

        // Unlock UI
        isTogglingPower = false

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasGivenInitialPowerHaptic = false
            self.hasGivenFinalPowerHaptic = false
        }
    }

    private func turnOff() async {
        print("🔘 turnOff() called via long press - isTogglingPower: \(isTogglingPower), isSettingBrightness: \(isSettingBrightness)")

        // Don't allow turning off while brightness is being set
        guard !isSettingBrightness else {
            print("❌ turnOff blocked: brightness is being set")
            return
        }

        guard let currentRoom = room,
              let groupedLight = currentRoom.groupedLights?.first else {
            print("❌ turnOff blocked: room=\(room != nil), groupedLights=\(room?.groupedLights != nil), count=\(room?.groupedLights?.count ?? 0)")
            return
        }

        print("✅ turnOff proceeding with groupedLight.id=\(groupedLight.id)")

        // Give initial haptic feedback
        if !hasGivenInitialPowerHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialPowerHaptic = true
        }

        // Set UI to OFF immediately (optimistic update)
        displayIsOn = false
        isTogglingPower = true

        // Clear scene colors since user is manually controlling the lights
        optimisticSceneColors = nil

        // Send API request to turn off
        do {
            try await HueAPIService.shared.setPower(groupedLightId: groupedLight.id, on: false)
            print("✅ Power off succeeded")

            // Update local state
            bridgeManager.updateLocalRoomState(roomId: roomId, on: false)

            // Give success haptic
            if !hasGivenFinalPowerHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalPowerHaptic = true
            }
        } catch {
            // Network failure - revert UI state if it was on before
            print("❌ Power off failed: \(error.localizedDescription)")
            // Check if light was actually on before we tried to turn it off
            if let lights = room?.groupedLights, !lights.isEmpty {
                displayIsOn = lights.contains { $0.on?.on == true }
            }
            WKInterfaceDevice.current().play(.failure)
        }

        // Unlock UI
        isTogglingPower = false

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasGivenInitialPowerHaptic = false
            self.hasGivenFinalPowerHaptic = false
        }
    }

    private func adjustBrightnessWithThrottle(delta: Double) async {
        guard let currentRoom = room,
              let groupedLight = currentRoom.groupedLights?.first else { return }

        isSettingBrightness = true
        defer { isSettingBrightness = false }

        // Clear scene colors since user is manually controlling the lights
        optimisticSceneColors = nil

        // Apply the multiplier to the delta
        let scaledDelta = delta * crownBrightnessDeltaMultiplier

        // Send the relative brightness adjustment
        do {
            try await HueAPIService.shared.adjustBrightness(groupedLightId: groupedLight.id, delta: scaledDelta)
            print("✅ Brightness adjusted by delta: \(scaledDelta)")

            // Success haptic - only give once per adjustment session
            if !hasGivenFinalBrightnessHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalBrightnessHaptic = true
            }

            // Note: We don't update local state here because:
            // 1. SSE will provide the real brightness value
            // 2. The UI brightness value is already updated optimistically via the crown binding
            // 3. Relative adjustments don't give us an absolute value to store

        } catch {
            print("❌ Brightness adjustment failed: \(error.localizedDescription)")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func setBrightness(_ value: Double) async {
        guard let currentRoom = room,
              let groupedLight = currentRoom.groupedLights?.first else { return }

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

        // Extract scene brightness before making API call
        let sceneBrightness = bridgeManager.extractAverageBrightnessFromScene(scene)

        let result = await bridgeManager.activateScene(scene.id)

        switch result {
        case .success:
            print("✅ Scene activated: \(scene.metadata.name)")
            activeSceneId = scene.id
            // Keep using scene colors - no need to revert to light data
            // The scene colors ARE the correct colors for this scene

            // Update brightness slider to match scene brightness
            if let sceneBrightness = sceneBrightness {
                // Set flag to prevent onChange from triggering API call
                isApplyingScene = true

                withAnimation(.easeInOut(duration: 0.3)) {
                    brightness = sceneBrightness
                    optimisticBrightness = sceneBrightness
                    displayIsOn = sceneBrightness > 0
                }
                print("💡 Updated brightness slider to scene value: \(sceneBrightness)%")

                // Reset flag after a short delay to allow onChange to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isApplyingScene = false
                }
            }

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
