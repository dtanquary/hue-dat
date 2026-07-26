//
//  GroupDetailView_macOS.swift
//  hue dat macOS
//
//  Unified group control view for rooms and zones with native macOS controls.
//  Replaces the previously separate RoomDetailView_macOS and ZoneDetailView_macOS.
//

import SwiftUI
import HueDatShared

struct GroupDetailView_macOS<T: GroupedLightContainer>: View {
    let groupId: String

    @Environment(BridgeManager.self) var bridgeManager

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hoveredSceneId: String?
    @State private var isApplyingScene = false
    @State private var activatingSceneId: String?

    @Namespace private var glassNamespace

    // Optimistic state for immediate UI feedback
    @State private var optimisticIsOn: Bool?
    @State private var optimisticBrightness: Double?

    // Guard against updating state after popover teardown
    @State private var isViewActive = false

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

    private var unknownName: String {
        T.isRoom ? "Unknown Room" : "Unknown Zone"
    }

    /// Scenes for this group, pinned scenes first (in pin order)
    private var groupScenes: [HueScene] {
        let all = bridgeManager.scenes.filter { $0.group.rid == groupId }
        let pinnedIds = bridgeManager.getPinnedScenes(forGroupId: groupId).map(\.id)
        let pinnedIdSet = Set(pinnedIds)
        let pinned = pinnedIds.compactMap { id in all.first(where: { $0.id == id }) }
        return pinned + all.filter { !pinnedIdSet.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: group?.metadata.name ?? unknownName, showsBack: true)

            // Layered controls section with ColorOrbsBackground
            GlassEffectContainer {
                ZStack {
                    // Layer 0: ColorOrbsBackground
                    ColorOrbsBackground_macOS(
                        baseColor: groupColor,
                        brightness: displayBrightness,
                        isOn: displayIsOn,
                        isActive: isViewActive
                    )
                    .frame(height: 280)

                    // Layer 1: Centered power toggle button
                    Button(action: {
                        togglePower(!displayIsOn)
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(displayIsOn ? .white : .white.opacity(0.5))
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(displayIsOn ? groupColor.opacity(0.65) : Color.clear).interactive(), in: .circle)
                    .glassEffectID("power", in: glassNamespace)
                    .accessibilityLabel(displayIsOn ? "Turn Off" : "Turn On")

                    // Layer 2: Brightness percentage overlay (morphs into the
                    // power circle when the lights go off)
                    if displayIsOn {
                        VStack {
                            Text(displayBrightness.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(displayBrightness))%" : String(format: "%.1f%%", displayBrightness))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect()
                                .glassEffectID("percent", in: glassNamespace)
                                .padding(.top, 16)

                            Spacer()
                        }
                        .transition(.opacity)
                    }

                    // Layer 3: Horizontal slider at bottom
                    if displayIsOn {
                        VStack {
                            Spacer()

                            HStack(spacing: 12) {
                                Image(systemName: "sun.min")
                                    .foregroundStyle(.white.opacity(0.8))
                                    .font(.body)

                                Slider(value: Binding(
                                    get: { displayBrightness },
                                    set: { newValue in
                                        setBrightness(newValue)
                                    }
                                ), in: 0...100)
                                .tint(.white)

                                Image(systemName: "sun.max.fill")
                                    .foregroundStyle(.white.opacity(0.8))
                                    .font(.body)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(in: .capsule)
                            .glassEffectID("slider", in: glassNamespace)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .frame(height: 280)

            // Divider before scenes section
            if !groupScenes.isEmpty {
                Divider()
            }

            // Scrollable scenes section
            ScrollView {
                VStack(spacing: 0) {
                    if !groupScenes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack {
                                Text("Scenes")
                                    .font(.headline)
                                Spacer()
                                Text("\(groupScenes.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                    sceneCard(for: scene)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            isViewActive = true
            loadGroupState()
        }
        .onDisappear {
            isViewActive = false
        }
        .onChange(of: groupedLight?.dimming?.brightness) { _, newBrightness in
            guard isViewActive else { return }
            if let newBrightness = newBrightness {
                brightness = newBrightness
            }
        }
        .onChange(of: groupedLight?.on?.on) { _, newIsOn in
            guard isViewActive else { return }
            if let newIsOn = newIsOn {
                isOn = newIsOn
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

    private func loadGroupState() {
        isOn = groupedLight?.on?.on ?? false
        brightness = groupedLight?.dimming?.brightness ?? 0.0
    }

    private func togglePower(_ newValue: Bool) {
        guard let lightId = groupedLightId else { return }

        // Optimistic update; animated so the %/slider glass morphs into the
        // power circle via the shared glassEffectIDs
        withAnimation(.spring(duration: 0.45)) {
            optimisticIsOn = newValue
        }

        Task {
            do {
                try await HueAPIService.shared.setPower(groupedLightId: lightId, on: newValue)
                guard isViewActive else { return }
                isOn = newValue
                optimisticIsOn = nil
            } catch {
                withAnimation(.spring(duration: 0.45)) {
                    optimisticIsOn = nil
                }
                guard isViewActive else { return }
                errorMessage = "Failed to toggle power: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func setBrightness(_ newValue: Double) {
        guard let lightId = groupedLightId else { return }

        // Don't trigger API call when applying scene brightness
        guard !isApplyingScene else { return }

        // Optimistic update
        optimisticBrightness = newValue

        // Debounce: only send request after user stops adjusting
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            // Check if value is still the same (user stopped adjusting)
            guard optimisticBrightness == newValue else { return }

            do {
                try await HueAPIService.shared.setBrightness(groupedLightId: lightId, brightness: newValue)
                guard isViewActive else { return }
                brightness = newValue
                optimisticBrightness = nil
            } catch {
                optimisticBrightness = nil
                guard isViewActive else { return }
                errorMessage = "Failed to set brightness: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func activateScene(_ scene: HueScene) {
        // Extract scene brightness for optimistic update
        let sceneBrightness = bridgeManager.extractAverageBrightnessFromScene(scene)

        // Optimistic updates - immediate UI feedback
        activatingSceneId = scene.id
        withAnimation(.spring(duration: 0.45)) {
            optimisticIsOn = true
        }
        if let sceneBrightness = sceneBrightness {
            optimisticBrightness = sceneBrightness
        }

        Task {
            defer { activatingSceneId = nil }
            do {
                try await HueAPIService.shared.activateScene(sceneId: scene.id)
                guard isViewActive else { return }

                isOn = true
                if let sceneBrightness = sceneBrightness {
                    isApplyingScene = true
                    brightness = sceneBrightness

                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard isViewActive else { return }
                        isApplyingScene = false
                    }
                }
                optimisticIsOn = nil
                optimisticBrightness = nil
            } catch {
                optimisticIsOn = nil
                optimisticBrightness = nil
                guard isViewActive else { return }
                errorMessage = "Failed to activate scene: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    @ViewBuilder
    private func sceneCard(for scene: HueScene) -> some View {
        SceneCardView_macOS(
            scene: scene,
            isActive: scene.status?.active == "active",
            isPinned: bridgeManager.isScenePinned(sceneId: scene.id, forGroupId: groupId),
            isHovered: hoveredSceneId == scene.id,
            isActivating: activatingSceneId == scene.id,
            onTap: { activateScene(scene) },
            onTogglePin: {
                withAnimation(.bouncy) {
                    bridgeManager.toggleScenePin(sceneId: scene.id, forGroupId: groupId)
                }
            },
            onHoverChange: { isHovered in
                hoveredSceneId = isHovered ? scene.id : nil
            }
        )
        .environment(bridgeManager)
    }
}

// MARK: - Scene Card View

struct SceneCardView_macOS: View {
    let scene: HueScene
    let isActive: Bool
    let isPinned: Bool
    let isHovered: Bool
    var isActivating: Bool = false
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onHoverChange: (Bool) -> Void

    @Environment(BridgeManager.self) var bridgeManager
    @State private var colors: [Color] = []

    private var gradientColors: [Color] {
        if colors.count >= 2 { return colors }
        if let single = colors.first { return [single, single.opacity(0.55)] }
        return [Color.gray.opacity(0.3), Color.gray.opacity(0.2)]
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // Palette-derived gradient background
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
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.ultraThinMaterial)

                VStack {
                    HStack {
                        // Pin indicator (top-left, matches iOS)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(.white)
                                .font(.caption)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .padding(8)
                                .symbolEffect(.bounce, value: isPinned)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Spacer()

                        // Checkmark for active scene (top-right)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                                .font(.body)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .padding(8)
                                .transition(.symbolEffect(.drawOn))
                        }
                    }
                    Spacer()
                }
                .animation(.spring(duration: 0.4), value: isActive)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.white.opacity(0.8) : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .scaleEffect(isActivating ? 0.96 : (isHovered ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.snappy(duration: 0.25), value: isActivating)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTogglePin) {
                Label(isPinned ? "Unpin Scene" : "Pin Scene",
                      systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
        .onHover(perform: onHoverChange)
        .onAppear {
            colors = bridgeManager.extractGradientColorsFromScene(scene)
        }
        .onChange(of: scene.id) {
            // LazyVGrid reuses cards; re-derive when the scene changes
            colors = bridgeManager.extractGradientColorsFromScene(scene)
        }
    }
}

// MARK: - Previews

#Preview("Room Detail") {
    @Previewable @State var manager: BridgeManager = {
        let mgr = BridgeManager()

        let sampleRoom = HueRoom(
            id: "preview-room-1",
            type: "room",
            metadata: HueRoom.RoomMetadata(name: "Living Room", archetype: "living_room"),
            children: nil,
            services: [HueRoom.HueRoomService(rid: "preview-light-1", rtype: "grouped_light")],
            groupedLights: [HueGroupedLight(
                id: "preview-light-1",
                type: "grouped_light",
                on: HueGroupedLight.GroupedLightOn(on: true),
                dimming: HueGroupedLight.GroupedLightDimming(brightness: 75.0),
                colorTemperature: nil,
                color: nil
            )]
        )

        mgr.rooms = [sampleRoom]

        return mgr
    }()

    NavigationStack {
        GroupDetailView_macOS<HueRoom>(groupId: "preview-room-1")
    }
    .environment(manager)
    .frame(width: 320, height: 480)
}

#Preview("Zone Detail") {
    @Previewable @State var manager: BridgeManager = {
        let mgr = BridgeManager()

        let sampleZone = HueZone(
            id: "preview-zone-1",
            type: "zone",
            metadata: HueZone.ZoneMetadata(name: "Upstairs", archetype: "home"),
            children: nil,
            services: [HueZone.HueZoneService(rid: "preview-light-1", rtype: "grouped_light")],
            groupedLights: [HueGroupedLight(
                id: "preview-light-1",
                type: "grouped_light",
                on: HueGroupedLight.GroupedLightOn(on: true),
                dimming: HueGroupedLight.GroupedLightDimming(brightness: 75.0),
                colorTemperature: nil,
                color: nil
            )]
        )

        mgr.zones = [sampleZone]

        return mgr
    }()

    NavigationStack {
        GroupDetailView_macOS<HueZone>(groupId: "preview-zone-1")
    }
    .environment(manager)
    .frame(width: 320, height: 480)
}
