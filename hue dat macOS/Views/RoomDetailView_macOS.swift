//
//  RoomDetailView_macOS.swift
//  hue dat macOS
//
//  Room control view with native macOS controls
//

import SwiftUI
import HueDatShared

struct RoomDetailView_macOS: View {
    let room: HueRoom
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

    private var groupedLight: HueGroupedLight? {
        room.groupedLights?.first
    }

    private var groupedLightId: String? {
        room.services?.first(where: { $0.rtype == "grouped_light" })?.rid
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
                    Image(systemName: iconForArchetype(room.metadata.archetype))
                        .foregroundColor(.accentColor)
                    Text(room.metadata.name)
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

            ScrollView {
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
                        ), in: 0...100, step: 1)
                        .disabled(!displayIsOn)
                    }

                // Scenes
                if !bridgeManager.scenes.filter({ $0.group.rid == room.id }).isEmpty {
                    Divider()

                    DisclosureGroup(
                        isExpanded: $isScenesExpanded,
                        content: {
                            VStack(spacing: 8) {
                                ForEach(bridgeManager.scenes.filter({ $0.group.rid == room.id })) { scene in
                                    sceneButton(for: scene)
                                }
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            HStack {
                                Text("Scenes")
                                    .font(.headline)
                                Spacer()
                                Text("\(bridgeManager.scenes.filter({ $0.group.rid == room.id }).count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    )
                }
                }
                .padding()
            }
        }
        .onAppear {
            loadRoomState()
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

    private func loadRoomState() {
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
    private func sceneButton(for scene: HueScene) -> some View {
        let isActive = scene.status?.active == "active"
        let isHovered = hoveredSceneId == scene.id

        Button(action: {
            activateScene(scene)
        }) {
            HStack {
                Text(scene.metadata.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(sceneButtonBackground)
            .background(sceneButtonBackgroundView(isActive: isActive, isHovered: isHovered))
            .overlay(sceneButtonOverlay(isActive: isActive))
            .cornerRadius(8)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: hoveredSceneId)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredSceneId = isHovered ? scene.id : nil
        }
    }

    private var sceneButtonBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    @ViewBuilder
    private func sceneButtonBackgroundView(isActive: Bool, isHovered: Bool) -> some View {
        if isActive {
            Color.accentColor.opacity(0.15)
        } else if isHovered {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func sceneButtonOverlay(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                lineWidth: 1.5
            )
    }

    private func iconForArchetype(_ archetype: String) -> String {
        switch archetype.lowercased() {
        case "living_room": return "sofa"
        case "bedroom": return "bed.double"
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower"
        case "office": return "desktopcomputer"
        case "dining": return "fork.knife"
        case "hallway": return "figure.walk"
        case "garage": return "car"
        default: return "lightbulb"
        }
    }
}

// Note: Preview commented out because models don't have memberwise initializers
// Uncomment after adding public initializers to HueRoom and HueGroupedLight in HueDatShared
//#Preview {
//    RoomDetailView_macOS(room: HueRoom(
//        id: "1",
//        type: "room",
//        metadata: HueRoom.RoomMetadata(name: "Living Room", archetype: "living_room"),
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
