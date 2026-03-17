//
//  GroupDetailView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI
import HueDatShared

struct GroupDetailView<T: GroupedLightContainer>: View {
    let groupId: String
    var bridgeManager: BridgeManager

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
    @State private var brightnessThrottleTask: Task<Void, Never>?
    @State private var isAdjustingBrightness = false
    @State private var brightnessPopoverTask: Task<Void, Never>?
    @State private var hasGivenInitialBrightnessHaptic = false
    @State private var hasGivenFinalBrightnessHaptic = false
    @State private var brightnessHapticResetTask: Task<Void, Never>?
    @State private var hasCompletedInitialLoad = false
    @FocusState private var isBrightnessFocused: Bool

    // Throttle state for crown adjustment
    @State private var lastBrightnessValue: Double = 0
    @State private var accumulatedDelta: Double = 0
    @State private var canSendBrightnessUpdate: Bool = true

    // Brightness optimistic state for instant UI updates
    @State private var optimisticBrightness: Double?

    // Scene picker state
    @State private var availableScenes: [HueScene] = []
    @State private var activeSceneId: String?
    @State private var showScenePicker: Bool = false
    @State private var hasFetchedScenes: Bool = false  // Guard to prevent duplicate fetchScenes calls
    @State private var isApplyingScene: Bool = false  // Guard to prevent onChange from firing during scene activation

    // Computed property to get live group data
    private var group: T? {
        if T.isRoom {
            return bridgeManager.rooms.first(where: { $0.id == groupId }) as? T
        } else {
            return bridgeManager.zones.first(where: { $0.id == groupId }) as? T
        }
    }

    /// Label for logging and UI text
    private var groupTypeLabel: String {
        T.isRoom ? "room" : "zone"
    }

    // Computed property for orb opacity (0.0 to 1.0)
    private var orbOpacity: Double {
        displayIsOn ? (brightness / 100.0) : 0.0
    }

    var body: some View {
        Group {
            if let group = group {
                groupContent(for: group)
            } else {
                VStack {
                    ProgressView()
                    Text("Loading \(groupTypeLabel)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    // If group is not found, try to refresh
                    if !T.isRoom {
                        Task {
                            debugLog("⚠️ \(groupTypeLabel.capitalized) \(groupId) not found, refreshing \(groupTypeLabel)s...")
                            await bridgeManager.getZones()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupContent(for group: T) -> some View {
        GeometryReader { outerGeometry in
            ZStack {
                // Layer 1: Brightness-controlled orange/grey orb background
                let groupedLight = group.groupedLights?.first
                let isOn = groupedLight?.on?.on ?? false
                let currentBrightness = groupedLight?.dimming?.brightness ?? 0.0

                ColorOrbsBackground(brightness: currentBrightness, isOn: isOn)
                    .opacity(orbOpacity)
                    .animation(.easeInOut(duration: 0.3), value: orbOpacity)
                    .zIndex(0)

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
                                    .foregroundStyle(.white)
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

            // Reset task for hiding popover
            brightnessPopoverTask?.cancel()
            brightnessPopoverTask = Task {
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAdjustingBrightness = false
                }
            }

            // Reset task for haptic flag - wait longer to ensure user is done adjusting
            brightnessHapticResetTask?.cancel()
            brightnessHapticResetTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                // Reset flags so next adjustment session gets haptics again
                hasGivenInitialBrightnessHaptic = false
                hasGivenFinalBrightnessHaptic = false
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
                brightnessThrottleTask?.cancel()
                brightnessThrottleTask = Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    canSendBrightnessUpdate = true

                    // If there's accumulated delta, send it now
                    if accumulatedDelta != 0 {
                        let deltaToSend = accumulatedDelta
                        accumulatedDelta = 0
                        canSendBrightnessUpdate = false

                        await adjustBrightnessWithThrottle(delta: deltaToSend)

                        // Re-open the gate after another throttle period
                        try? await Task.sleep(for: .seconds(0.5))
                        guard !Task.isCancelled else { return }
                        canSendBrightnessUpdate = true
                    }
                }
            }
            // If gate is closed, delta is already accumulated above, just wait for task
        }
        .navigationTitle(group.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize UI from cached data only (no API call)
            if let lights = group.groupedLights, !lights.isEmpty {
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
                    brightnessPopoverTask?.cancel()
                    brightnessPopoverTask = Task {
                        try? await Task.sleep(for: .seconds(1.0))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isAdjustingBrightness = false
                        }
                    }
                }
            }

            // Load scenes for this group (guard against duplicate calls)
            Task {
                guard !hasFetchedScenes else {
                    debugLog("⏭️ GroupDetailView<\(T.apiGroupType)>: Skipping duplicate fetchScenes call")
                    return
                }
                hasFetchedScenes = true

                // Fetch scenes
                if T.isRoom {
                    availableScenes = await bridgeManager.fetchScenes(forRoomId: groupId)
                } else {
                    availableScenes = await bridgeManager.fetchScenes(forZoneId: groupId)
                }
            }

            // Mark initial load as complete AFTER a brief delay to ensure programmatic brightness changes don't trigger haptics
            Task {
                try? await Task.sleep(for: .seconds(0.1))
                hasCompletedInitialLoad = true
            }
        }
    }

    // MARK: - Power Control

    private func togglePower() async {
        let label = groupTypeLabel
        debugLog("🔘 togglePower() called - displayIsOn: \(displayIsOn), isTogglingPower: \(isTogglingPower), isSettingBrightness: \(isSettingBrightness)")

        // Don't allow toggling power while brightness is being set
        guard !isSettingBrightness else {
            debugLog("❌ togglePower blocked: brightness is being set")
            return
        }

        guard let currentGroup = group,
              let groupedLight = currentGroup.groupedLights?.first else {
            debugLog("❌ togglePower blocked: \(label)=\(group != nil), groupedLights=\(group?.groupedLights != nil), count=\(group?.groupedLights?.count ?? 0)")
            return
        }

        debugLog("✅ togglePower proceeding with groupedLight.id=\(groupedLight.id)")

        // Give initial haptic feedback
        if !hasGivenInitialPowerHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialPowerHaptic = true
        }

        // Flip UI immediately (optimistic update)
        displayIsOn = !displayIsOn
        isTogglingPower = true

        // Send API request directly to HueAPIService - only revert on network failure
        do {
            try await HueAPIService.shared.setPower(groupedLightId: groupedLight.id, on: displayIsOn)
            debugLog("✅ Power toggle succeeded: \(displayIsOn ? "ON" : "OFF")")

            // If we just turned ON the light, fetch the current brightness from the bridge
            if displayIsOn {
                if let updatedGroupedLight = await bridgeManager.fetchGroupedLight(groupedLightId: groupedLight.id) {
                    if let currentBrightness = updatedGroupedLight.dimming?.brightness {
                        debugLog("🔄 Fetched brightness after power on: \(Int(currentBrightness))%")
                        // Update brightness with animation to ensure orb opacity updates smoothly
                        withAnimation(.easeInOut(duration: 0.3)) {
                            brightness = currentBrightness
                        }
                        updateLocalState(on: displayIsOn, brightness: currentBrightness)
                    } else {
                        updateLocalState(on: displayIsOn)
                    }
                } else {
                    // Fetch failed, just update on state
                    updateLocalState(on: displayIsOn)
                }
            } else {
                // Light was turned OFF, just update the on state
                updateLocalState(on: displayIsOn)
            }

            // Give success haptic
            if !hasGivenFinalPowerHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalPowerHaptic = true
            }
        } catch {
            // Network failure - revert UI state
            debugLog("❌ Power toggle failed: \(error.localizedDescription)")
            displayIsOn = !displayIsOn  // Revert to previous state
            WKInterfaceDevice.current().play(.failure)
        }

        // Unlock UI
        isTogglingPower = false

        // Reset haptic flags after a delay
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            hasGivenInitialPowerHaptic = false
            hasGivenFinalPowerHaptic = false
        }
    }

    private func turnOff() async {
        let label = groupTypeLabel
        debugLog("🔘 turnOff() called via long press - isTogglingPower: \(isTogglingPower), isSettingBrightness: \(isSettingBrightness)")

        // Don't allow turning off while brightness is being set
        guard !isSettingBrightness else {
            debugLog("❌ turnOff blocked: brightness is being set")
            return
        }

        guard let currentGroup = group,
              let groupedLight = currentGroup.groupedLights?.first else {
            debugLog("❌ turnOff blocked: \(label)=\(group != nil), groupedLights=\(group?.groupedLights != nil), count=\(group?.groupedLights?.count ?? 0)")
            return
        }

        debugLog("✅ turnOff proceeding with groupedLight.id=\(groupedLight.id)")

        // Give initial haptic feedback
        if !hasGivenInitialPowerHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialPowerHaptic = true
        }

        // Set UI to OFF immediately (optimistic update)
        displayIsOn = false
        isTogglingPower = true

        // Send API request to turn off
        do {
            try await HueAPIService.shared.setPower(groupedLightId: groupedLight.id, on: false)
            debugLog("✅ Power off succeeded")

            // Update local state
            updateLocalState(on: false)

            // Give success haptic
            if !hasGivenFinalPowerHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalPowerHaptic = true
            }
        } catch {
            // Network failure - revert UI state if it was on before
            debugLog("❌ Power off failed: \(error.localizedDescription)")
            // Check if light was actually on before we tried to turn it off
            if let lights = group?.groupedLights, !lights.isEmpty {
                displayIsOn = lights.contains { $0.on?.on == true }
            }
            WKInterfaceDevice.current().play(.failure)
        }

        // Unlock UI
        isTogglingPower = false

        // Reset haptic flags after a delay
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            hasGivenInitialPowerHaptic = false
            hasGivenFinalPowerHaptic = false
        }
    }

    // MARK: - Brightness Control

    private func adjustBrightnessWithThrottle(delta: Double) async {
        guard let currentGroup = group,
              let groupedLight = currentGroup.groupedLights?.first else { return }

        isSettingBrightness = true
        defer { isSettingBrightness = false }

        // Apply the multiplier to the delta
        let scaledDelta = delta * crownBrightnessDeltaMultiplier

        // Send the relative brightness adjustment
        do {
            try await HueAPIService.shared.adjustBrightness(groupedLightId: groupedLight.id, delta: scaledDelta)
            debugLog("✅ Brightness adjusted by delta: \(scaledDelta)")

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
            debugLog("❌ Brightness adjustment failed: \(error.localizedDescription)")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func setBrightness(_ value: Double) async {
        guard let currentGroup = group,
              let groupedLight = currentGroup.groupedLights?.first else { return }

        isSettingBrightness = true
        defer { isSettingBrightness = false }

        // Save previous state for rollback on failure
        let previousDisplayIsOn = displayIsOn
        let previousOptimisticBrightness = optimisticBrightness

        // If light is OFF, we need to turn it ON first with the target brightness
        if !displayIsOn {
            // Optimistic updates for turning on + setting brightness
            displayIsOn = true
            optimisticBrightness = value

            let result = await bridgeManager.setGroupedLightPowerAndBrightness(id: groupedLight.id, on: true, brightness: value)

            switch result {
            case .success:
                // Update local state in BridgeManager so list view reflects the change
                updateLocalState(on: true, brightness: value)

                // Clear optimistic state
                optimisticBrightness = nil
                // Success haptic
                if !hasGivenFinalBrightnessHaptic {
                    WKInterfaceDevice.current().play(.success)
                    hasGivenFinalBrightnessHaptic = true
                }
            case .failure(let error):
                debugLog("❌ setBrightness (power+brightness) failed: \(error.localizedDescription)")
                // Rollback optimistic state
                displayIsOn = previousDisplayIsOn
                optimisticBrightness = previousOptimisticBrightness
                WKInterfaceDevice.current().play(.failure)
            }
        } else {
            // Light is already ON, just set brightness
            // Optimistic update
            optimisticBrightness = value

            let result = await bridgeManager.setGroupedLightBrightness(id: groupedLight.id, brightness: value)

            switch result {
            case .success:
                // Update local state in BridgeManager so list view reflects the change
                updateLocalState(brightness: value)

                // Clear optimistic state
                optimisticBrightness = nil
                // Success haptic
                if !hasGivenFinalBrightnessHaptic {
                    WKInterfaceDevice.current().play(.success)
                    hasGivenFinalBrightnessHaptic = true
                }
            case .failure(let error):
                debugLog("❌ setBrightness failed: \(error.localizedDescription)")
                // Rollback optimistic state
                optimisticBrightness = previousOptimisticBrightness
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    // MARK: - Local State Update Helper

    /// Routes local state updates to the correct BridgeManager method based on group type
    private func updateLocalState(on: Bool? = nil, brightness: Double? = nil) {
        if T.isRoom {
            bridgeManager.updateLocalRoomState(roomId: groupId, on: on, brightness: brightness)
        } else {
            bridgeManager.updateLocalZoneState(zoneId: groupId, on: on, brightness: brightness)
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
        debugLog("🎬 Activating scene: \(scene.metadata.name)")

        // Extract scene brightness before making API call
        let sceneBrightness = bridgeManager.extractAverageBrightnessFromScene(scene)

        let result = await bridgeManager.activateScene(scene.id)

        switch result {
        case .success:
            debugLog("✅ Scene activated: \(scene.metadata.name)")
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
                debugLog("💡 Updated brightness slider to scene value: \(sceneBrightness)%")

                // Reset flag after a short delay to allow onChange to complete
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    isApplyingScene = false
                }
            }

        case .failure(let error):
            debugLog("❌ Failed to activate scene: \(error.localizedDescription)")
            // Scene activation failed, continue without showing error
        }
    }

    // MARK: - Actions
    // Note: Light control actions now use centralized BridgeManager methods
    // (setGroupedLightPower, setGroupedLightBrightness, setGroupedLightPowerAndBrightness)
    // which provide automatic rate limiting (1 command/sec for grouped lights)

}
