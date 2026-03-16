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
    let onBack: () -> Void

    @EnvironmentObject var bridgeManager: BridgeManager

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hoveredSceneId: String?
    @State private var isApplyingScene = false

    // Optimistic state for immediate UI feedback
    @State private var optimisticIsOn: Bool?
    @State private var optimisticBrightness: Double?

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

    private var displayIsOn: Bool {
        optimisticIsOn ?? isOn
    }

    private var displayBrightness: Double {
        optimisticBrightness ?? brightness
    }

    private var groupIcon: String {
        if T.isRoom {
            return iconForArchetype(group?.metadata.archetype ?? "")
        } else {
            return "square.grid.2x2"
        }
    }

    private var unknownName: String {
        T.isRoom ? "Unknown Room" : "Unknown Zone"
    }

    private var groupScenes: [HueScene] {
        bridgeManager.scenes.filter { $0.group.rid == groupId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: groupIcon)
                        .foregroundStyle(Color.accentColor)
                    Text(group?.metadata.name ?? unknownName)
                        .font(.headline)
                }

                Spacer()

                // Invisible spacer to center title
                Button("") { }
                    .buttonStyle(.plain)
                    .opacity(0)
                    .disabled(true)
                    .allowsHitTesting(false)
            }
            .padding()
            .zIndex(999)  // Ensure header is always on top for hit testing

            Divider()

            // Layered controls section with ColorOrbsBackground
            ZStack {
                // Layer 0: ColorOrbsBackground
                ColorOrbsBackground_macOS(
                    brightness: displayBrightness,
                    isOn: displayIsOn
                )
                .frame(height: 280)
                .allowsHitTesting(false)  // Don't block header clicks

                // Layer 1: Centered power toggle button
                VStack {
                    Spacer()

                    Button(action: {
                        togglePower(!displayIsOn)
                    }) {
                        Image(systemName: displayIsOn ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(displayIsOn ? .white : .gray)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Layer 2: Brightness percentage overlay
                VStack {
                    HStack {
                        Spacer()

                        Text(displayBrightness.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(displayBrightness))%" : String(format: "%.1f%%", displayBrightness))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 4)

                        Spacer()
                    }
                    .padding(.top, 16)

                    Spacer()
                }

                // Layer 3: Horizontal slider at bottom
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
                        .disabled(!displayIsOn)
                        .tint(.white)

                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.body)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
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
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
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
            loadGroupState()
        }
        .onChange(of: groupedLight?.dimming?.brightness) { _, newBrightness in
            if let newBrightness = newBrightness {
                brightness = newBrightness
            }
        }
        .onChange(of: groupedLight?.on?.on) { _, newIsOn in
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

        // Optimistic update
        optimisticIsOn = newValue

        Task {
            do {
                try await HueAPIService.shared.setPower(groupedLightId: lightId, on: newValue)
                isOn = newValue
                optimisticIsOn = nil
            } catch {
                optimisticIsOn = nil
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
                brightness = newValue
                optimisticBrightness = nil
            } catch {
                optimisticBrightness = nil
                errorMessage = "Failed to set brightness: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func activateScene(_ scene: HueScene) {
        // Extract scene brightness for optimistic update
        let sceneBrightness = bridgeManager.extractAverageBrightnessFromScene(scene)

        // Optimistic updates - immediate UI feedback
        optimisticIsOn = true
        if let sceneBrightness = sceneBrightness {
            optimisticBrightness = sceneBrightness
        }

        Task {
            do {
                try await HueAPIService.shared.activateScene(sceneId: scene.id)

                isOn = true
                if let sceneBrightness = sceneBrightness {
                    isApplyingScene = true
                    brightness = sceneBrightness

                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        isApplyingScene = false
                    }
                }
                optimisticIsOn = nil
                optimisticBrightness = nil
            } catch {
                optimisticIsOn = nil
                optimisticBrightness = nil
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
            isHovered: hoveredSceneId == scene.id,
            onTap: { activateScene(scene) },
            onHoverChange: { isHovered in
                hoveredSceneId = isHovered ? scene.id : nil
            }
        )
        .environmentObject(bridgeManager)
    }
}

// MARK: - Scene Card View

struct SceneCardView_macOS: View {
    let scene: HueScene
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void

    @EnvironmentObject var bridgeManager: BridgeManager
    @State private var colors: [Color] = []

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // Background with color stripes or default material
                if !colors.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(0..<colors.count, id: \.self) { index in
                            colors[index]
                        }
                    }
                } else {
                    Color.gray.opacity(0.3)
                }

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
                .background(.ultraThinMaterial.opacity(0.9))

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
                        }
                        Spacer()
                    }
                }
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
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHoverChange)
        .onAppear {
            // Extract colors only once when view appears
            colors = bridgeManager.extractColorsFromScene(scene)
        }
    }
}

// MARK: - Previews

#Preview("Room Detail") {
    @Previewable @StateObject var manager: BridgeManager = {
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

    GroupDetailView_macOS<HueRoom>(
        groupId: "preview-room-1",
        onBack: {}
    )
    .environmentObject(manager)
    .frame(width: 320, height: 480)
}

#Preview("Zone Detail") {
    @Previewable @StateObject var manager: BridgeManager = {
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

    GroupDetailView_macOS<HueZone>(
        groupId: "preview-zone-1",
        onBack: {}
    )
    .environmentObject(manager)
    .frame(width: 320, height: 480)
}
