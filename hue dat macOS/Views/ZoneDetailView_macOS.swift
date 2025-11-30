//
//  ZoneDetailView_macOS.swift
//  hue dat macOS
//
//  Zone control view with native macOS controls
//

import SwiftUI
import HueDatShared

struct ZoneDetailView_macOS: View {
    let zoneId: String
    let onBack: () -> Void

    @EnvironmentObject var bridgeManager: BridgeManager

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var isScenesExpanded = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hoveredSceneId: String?
    @State private var isApplyingScene = false

    // Optimistic state for immediate UI feedback
    @State private var optimisticIsOn: Bool?
    @State private var optimisticBrightness: Double?

    // Drag gesture state for brightness bar
    @State private var isDraggingBrightness = false
    @State private var dragStartY: CGFloat? = nil
    @State private var dragStartBrightness: Double = 0.0

    private var zone: HueZone? {
        bridgeManager.zones.first(where: { $0.id == zoneId })
    }

    private var groupedLight: HueGroupedLight? {
        zone?.groupedLights?.first
    }

    private var groupedLightId: String? {
        zone?.services?.first(where: { $0.rtype == "grouped_light" })?.rid
    }

    private var displayIsOn: Bool {
        optimisticIsOn ?? isOn
    }

    private var displayBrightness: Double {
        optimisticBrightness ?? brightness
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
                    Image(systemName: "square.grid.2x2")
                        .foregroundColor(.accentColor)
                    Text(zone?.metadata.name ?? "Unknown Zone")
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
                            .foregroundColor(displayIsOn ? .white : .gray)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Layer 2: Brightness drag bar on right side
                HStack {
                    Spacer()

                    VStack(spacing: 8) {
                        Spacer()

                        // Brightness bar track
                        ZStack(alignment: .bottom) {
                            // Background track
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 40, height: 200)

                            // Fill based on brightness
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 40, height: 200 * (displayBrightness / 100.0))
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragStartY == nil {
                                        dragStartY = value.startLocation.y
                                        dragStartBrightness = displayBrightness
                                    }

                                    guard let startY = dragStartY else { return }

                                    // Calculate brightness based on vertical drag
                                    // Inverted: dragging up increases brightness
                                    let dragDistance = startY - value.location.y
                                    let brightnessChange = (dragDistance / 200.0) * 100.0
                                    let newBrightness = max(1.0, min(100.0, dragStartBrightness + brightnessChange))

                                    setBrightness(newBrightness)
                                }
                                .onEnded { _ in
                                    dragStartY = nil
                                    dragStartBrightness = 0.0
                                }
                        )

                        Spacer()
                    }
                    .padding(.trailing, 16)
                }

                // Layer 3: Brightness percentage overlay
                VStack {
                    HStack {
                        Spacer()

                        Text("\(Int(displayBrightness))%")
                            .font(.headline)
                            .foregroundColor(.white)
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

                // Layer 4: Horizontal slider at bottom
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "sun.min")
                            .foregroundColor(.white.opacity(0.8))
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
                            .foregroundColor(.white.opacity(0.8))
                            .font(.body)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .frame(height: 280)

            // Divider before scenes section
            if !bridgeManager.scenes.filter({ $0.group.rid == zoneId }).isEmpty {
                Divider()
            }

            // Scrollable scenes section
            ScrollView {
                VStack(spacing: 0) {
                    if !bridgeManager.scenes.filter({ $0.group.rid == zoneId }).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack {
                                Text("Scenes")
                                    .font(.headline)
                                Spacer()
                                Text("\(bridgeManager.scenes.filter({ $0.group.rid == zoneId }).count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                                ForEach(bridgeManager.scenes.filter({ $0.group.rid == zoneId })) { scene in
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
            loadZoneState()
        }
        .onChange(of: groupedLight?.dimming?.brightness) { newBrightness in
            if let newBrightness = newBrightness {
                brightness = newBrightness
            }
        }
        .onChange(of: groupedLight?.on?.on) { newIsOn in
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

    private func loadZoneState() {
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
                // Update actual state
                await MainActor.run {
                    isOn = newValue
                    optimisticIsOn = nil
                }
            } catch {
                // Rollback optimistic update
                await MainActor.run {
                    optimisticIsOn = nil
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

        // Optimistic update
        optimisticBrightness = newValue

        // Debounce: only send request after user stops adjusting
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            // Check if value is still the same (user stopped adjusting)
            guard optimisticBrightness == newValue else { return }

            do {
                try await HueAPIService.shared.setBrightness(groupedLightId: lightId, brightness: newValue)
                // Update actual state
                await MainActor.run {
                    brightness = newValue
                    optimisticBrightness = nil
                }
            } catch {
                // Rollback optimistic update
                await MainActor.run {
                    optimisticBrightness = nil
                    errorMessage = "Failed to set brightness: \(error.localizedDescription)"
                    showError = true
                }
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

                // Update actual state after successful activation
                await MainActor.run {
                    isOn = true
                    if let sceneBrightness = sceneBrightness {
                        // Set flag to prevent onChange from triggering API call
                        isApplyingScene = true
                        brightness = sceneBrightness

                        // Reset flag after brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isApplyingScene = false
                        }
                    }
                    // Clear optimistic state
                    optimisticIsOn = nil
                    optimisticBrightness = nil
                }
            } catch {
                // Rollback optimistic updates on error
                await MainActor.run {
                    optimisticIsOn = nil
                    optimisticBrightness = nil
                    errorMessage = "Failed to activate scene: \(error.localizedDescription)"
                    showError = true
                }
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

#Preview {
    @Previewable @StateObject var manager: BridgeManager = {
        let mgr = BridgeManager()

        // Add sample zone data
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
                color_temperature: nil,
                color: nil
            )]
        )

        mgr.zones = [sampleZone]

        return mgr
    }()

    ZoneDetailView_macOS(
        zoneId: "preview-zone-1",
        onBack: {}
    )
    .environmentObject(manager)
    .frame(width: 320, height: 480)
}
