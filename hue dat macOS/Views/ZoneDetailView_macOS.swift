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
                .buttonStyle(.plain)

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
            }
            .padding()

            Divider()

            // Fixed controls section (power + brightness)
            VStack(spacing: 24) {
                // Power toggle
                HStack {
                    Text("Power")
                        .font(.headline)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { displayIsOn },
                        set: { newValue in
                            togglePower(newValue)
                        }
                    ))
                    .toggleStyle(.switch)
                }

                // Brightness slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Brightness")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(displayBrightness))%")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: Binding(
                        get: { displayBrightness },
                        set: { newValue in
                            setBrightness(newValue)
                        }
                    ), in: 0...100)
                    .disabled(!displayIsOn)
                }
            }
            .padding()

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
        let isActive = scene.status?.active == "active"
        let isHovered = hoveredSceneId == scene.id
        let colors = bridgeManager.extractColorsFromScene(scene)

        Button(action: {
            activateScene(scene)
        }) {
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
                        .foregroundColor(.white)
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
                                .foregroundColor(.white)
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
        .onHover { isHovered in
            hoveredSceneId = isHovered ? scene.id : nil
        }
    }
}

// Note: Preview commented out because models don't have memberwise initializers
// Uncomment after adding public initializers to HueZone and HueGroupedLight in HueDatShared
//#Preview {
//    ZoneDetailView_macOS(zone: HueZone(
//        id: "1",
//        type: "zone",
//        metadata: HueZone.ZoneMetadata(name: "Upstairs", archetype: "home"),
//        children: nil,
//        services: nil,
//        groupedLights: [HueGroupedLight(
//            id: "1",
//            type: "grouped_light",
//            on: HueGroupedLight.GroupedLightOn(on: true),
//            dimming: HueGroupedLight.GroupedLightDimming(brightness: 75.0),
//            color_temperature: nil,
//            color: nil
//        )]
//    ))
//    .environmentObject(BridgeManager())
//}
