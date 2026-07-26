//
//  GroupDetailView_iOS.swift
//  hue dat iOS
//
//  Unified room/zone control view with native iOS controls.
//  Replaces RoomDetailView_iOS and ZoneDetailView_iOS.
//

import SwiftUI
import HueDatShared

struct GroupDetailView_iOS<T: GroupedLightContainer>: View {
    let groupId: String

    @Environment(BridgeManager.self) var bridgeManager

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isApplyingScene = false
    @State private var isViewActive = true

    // Haptic triggers (counters so repeated events re-fire)
    @State private var powerHapticCount = 0
    @State private var actionErrorCount = 0
    @State private var sceneSuccessCount = 0
    @State private var pinHapticCount = 0
    @State private var brightnessCommitCount = 0

    // Scene card press feedback
    @State private var activatingSceneId: String?

    // Glass morphing between hero controls when power toggles
    @Namespace private var glassNamespace

    // Optimistic state for immediate UI feedback
    @State private var optimisticIsOn: Bool?
    @State private var optimisticBrightness: Double?

    // Task tracking for cleanup
    @State private var brightnessTask: Task<Void, Never>?
    @State private var sceneTask: Task<Void, Never>?
    @State private var powerTask: Task<Void, Never>?
    @State private var sceneResetTask: Task<Void, Never>?

    private var group: T? {
        if T.isRoom {
            return bridgeManager.rooms.first(where: { $0.id == groupId }) as? T
        } else {
            return bridgeManager.zones.first(where: { $0.id == groupId }) as? T
        }
    }

    private var groupedLight: HueGroupedLight? {
        group?.groupedLights?.first
    }

    private var groupedLightId: String? {
        group?.services?.first(where: { $0.rtype == "grouped_light" })?.rid
    }

    /// Live color the group's lights are actually showing right now
    private var groupColor: Color {
        groupedLight?.displayColor ?? .orange
    }

    private var displayIsOn: Bool {
        optimisticIsOn ?? isOn
    }

    private var displayBrightness: Double {
        optimisticBrightness ?? brightness
    }

    private var groupScenes: [HueScene] {
        bridgeManager.scenes.filter { $0.group.rid == groupId }
    }

    private var groupIcon: String {
        if T.isRoom {
            return iconForArchetype(group?.metadata.archetype ?? "")
        } else {
            return "square.grid.2x2"
        }
    }

    private var unknownLabel: String {
        T.isRoom ? "Unknown Room" : "Unknown Zone"
    }

    var body: some View {
        ZStack {
            // Background
            ColorOrbsBackground_iOS(
                baseColor: groupColor,
                brightness: displayBrightness,
                isOn: displayIsOn,
                isActive: isViewActive
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Controls hero — shared glassEffectIDs let the % badge and
                // slider morph into the power circle when the group turns off
                GlassEffectContainer(spacing: 24) {
                    VStack(spacing: 24) {
                        // Brightness percentage display
                        if displayIsOn {
                            Text(displayBrightness.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(displayBrightness))%" : String(format: "%.1f%%", displayBrightness))
                                .font(.title.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .glassEffect()
                                .glassEffectID("percent", in: glassNamespace)
                        }

                        // Power toggle button, tinted with the live light color
                        Button(action: {
                            togglePower(!displayIsOn)
                        }) {
                            Image(systemName: "power")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundStyle(displayIsOn ? .white : .gray)
                                .padding(28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(displayIsOn ? groupColor.opacity(0.65) : Color.clear).interactive(), in: .circle)
                        .glassEffectID("power", in: glassNamespace)

                        // Brightness slider
                        if displayIsOn {
                            HStack(spacing: 16) {
                                Image(systemName: "sun.min")
                                    .foregroundStyle(.white.opacity(0.8))
                                    .font(.title2)

                                Slider(value: Binding(
                                    get: { displayBrightness },
                                    set: { newValue in
                                        setBrightness(newValue)
                                    }
                                ), in: 1...100)
                                .tint(.white)

                                Image(systemName: "sun.max.fill")
                                    .foregroundStyle(.white.opacity(0.8))
                                    .font(.title2)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .glassEffect(in: .capsule)
                            .glassEffectID("slider", in: glassNamespace)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 32)
                }

                // Scenes section
                if !groupScenes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack {
                                Text("Scenes")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(groupScenes.count)")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glassEffect(in: .capsule)
                            }

                            // Grid of scene cards
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(groupScenes) { scene in
                                    SceneCard_iOS(
                                        scene: scene,
                                        groupId: groupId,
                                        isActivating: activatingSceneId == scene.id,
                                        onActivate: { activateScene(scene) },
                                        onTogglePin: {
                                            pinHapticCount += 1
                                            withAnimation(.bouncy) {
                                                bridgeManager.toggleScenePin(sceneId: scene.id, forGroupId: groupId)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    .scrollEdgeEffectStyle(.soft, for: .top)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: powerHapticCount)
        .sensoryFeedback(.success, trigger: sceneSuccessCount)
        .sensoryFeedback(.error, trigger: actionErrorCount)
        .sensoryFeedback(.impact(weight: .light), trigger: pinHapticCount)
        .sensoryFeedback(.selection, trigger: brightnessCommitCount)
        .navigationTitle(group?.metadata.name ?? unknownLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: groupIcon)
                        .foregroundStyle(.white)
                    Text(group?.metadata.name ?? unknownLabel)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            isViewActive = true
            loadGroupState()
        }
        .onDisappear {
            isViewActive = false
            // Cancel any running tasks
            brightnessTask?.cancel()
            sceneTask?.cancel()
            powerTask?.cancel()
            sceneResetTask?.cancel()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadGroupState() {
        isOn = groupedLight?.on?.on ?? false
        brightness = groupedLight?.dimming?.brightness ?? 0.0
    }

    private func togglePower(_ newValue: Bool) {
        guard let lightId = groupedLightId else { return }

        // Cancel any existing power task
        powerTask?.cancel()

        powerHapticCount += 1

        // Optimistic update, animated so the hero glass morphs
        withAnimation(.spring(duration: 0.45)) {
            optimisticIsOn = newValue
        }

        powerTask = Task {
            do {
                try await HueAPIService.shared.setPower(groupedLightId: lightId, on: newValue)
                // Update actual state only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    isOn = newValue
                    optimisticIsOn = nil
                }
            } catch {
                // Rollback optimistic update only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    withAnimation(.spring(duration: 0.45)) {
                        optimisticIsOn = nil
                    }
                    actionErrorCount += 1
                    errorMessage = "Failed to toggle power: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func setBrightness(_ newValue: Double) {
        guard let lightId = groupedLightId else { return }

        // Don't trigger API call when applying scene brightness
        guard !isApplyingScene else { return }

        // Cancel any existing brightness task
        brightnessTask?.cancel()

        // Optimistic update
        optimisticBrightness = newValue

        // Debounce: only send request after user stops adjusting
        brightnessTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            // Check if value is still the same (user stopped adjusting) and view is active
            guard !Task.isCancelled, isViewActive, optimisticBrightness == newValue else { return }

            do {
                try await HueAPIService.shared.setBrightness(groupedLightId: lightId, brightness: newValue)
                // Update actual state only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    brightness = newValue
                    optimisticBrightness = nil
                    brightnessCommitCount += 1
                }
            } catch {
                // Rollback optimistic update only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    optimisticBrightness = nil
                    actionErrorCount += 1
                    errorMessage = "Failed to set brightness: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func activateScene(_ scene: HueScene) {
        // Extract scene brightness for optimistic update
        let sceneBrightness = bridgeManager.extractAverageBrightnessFromScene(scene)

        // Cancel any existing scene task
        sceneTask?.cancel()

        // Optimistic updates - immediate UI feedback
        activatingSceneId = scene.id
        withAnimation(.spring(duration: 0.45)) {
            optimisticIsOn = true
        }
        if let sceneBrightness = sceneBrightness {
            optimisticBrightness = sceneBrightness
        }

        sceneTask = Task {
            do {
                try await HueAPIService.shared.activateScene(sceneId: scene.id)

                // Update actual state after successful activation, only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    activatingSceneId = nil
                    sceneSuccessCount += 1
                    isOn = true
                    if let sceneBrightness = sceneBrightness {
                        // Set flag to prevent onChange from triggering API call
                        isApplyingScene = true
                        brightness = sceneBrightness

                        // Reset flag after brief delay
                        sceneResetTask?.cancel()
                        sceneResetTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            guard !Task.isCancelled, isViewActive else { return }
                            isApplyingScene = false
                        }
                    }
                    // Clear optimistic state
                    optimisticIsOn = nil
                    optimisticBrightness = nil
                }
            } catch {
                // Rollback optimistic updates on error, only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    activatingSceneId = nil
                    actionErrorCount += 1
                    withAnimation(.spring(duration: 0.45)) {
                        optimisticIsOn = nil
                    }
                    optimisticBrightness = nil
                    errorMessage = "Failed to activate scene: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

}

/// Scene card with a soft gradient built from the scene's palette (or per-action
/// colors as fallback). Colors are cached in @State so they aren't re-derived on
/// every render (mirrors SceneCardView_macOS).
private struct SceneCard_iOS: View {
    let scene: HueScene
    let groupId: String
    let isActivating: Bool
    let onActivate: () -> Void
    let onTogglePin: () -> Void

    @Environment(BridgeManager.self) private var bridgeManager
    @State private var colors: [Color] = []

    private var isActive: Bool {
        scene.status?.active == "active"
    }

    private var isPinned: Bool {
        bridgeManager.isScenePinned(sceneId: scene.id, forGroupId: groupId)
    }

    private var gradientColors: [Color] {
        if colors.isEmpty {
            return [Color.gray.opacity(0.35), Color.gray.opacity(0.2)]
        }
        if colors.count == 1 {
            return [colors[0], colors[0].opacity(0.55)]
        }
        return colors
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Soft gradient wash from the scene's colors
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Scene name overlay at bottom
            HStack {
                Text(scene.metadata.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .glassEffect(in: .rect)

            // Pin indicator (top-left)
            if isPinned {
                VStack {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.white)
                            .font(.body)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(8)
                            .symbolEffect(.bounce, value: isPinned)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Checkmark for active scene (top-right)
            if isActive {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .font(.body)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(8)
                            .transition(.symbolEffect(.drawOn))
                    }
                    Spacer()
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isActive ? Color.white.opacity(0.8) : Color.clear,
                    lineWidth: 2.5
                )
        )
        .scaleEffect(isActivating ? 0.96 : 1.0)
        .animation(.snappy(duration: 0.25), value: isActivating)
        .animation(.spring(duration: 0.4), value: isActive)
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onTogglePin()
        }
        .accessibilityLabel(scene.metadata.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Activates scene. Long press to pin.")
        .onAppear {
            colors = bridgeManager.extractGradientColorsFromScene(scene)
        }
        .onChange(of: scene.id) {
            colors = bridgeManager.extractGradientColorsFromScene(scene)
        }
    }
}
