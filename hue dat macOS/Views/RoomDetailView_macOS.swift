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

    @EnvironmentObject var bridgeManager: BridgeManager
    @Environment(\.dismiss) private var dismiss

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var selectedSceneId: String?
    @State private var showError = false
    @State private var errorMessage = ""

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
            // Header
            HStack {
                Image(systemName: iconForArchetype(room.metadata.archetype))
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text(room.metadata.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
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

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Scenes")
                                .font(.headline)

                            ForEach(bridgeManager.scenes.filter({ $0.group.rid == room.id })) { scene in
                                Button(action: {
                                    activateScene(scene)
                                }) {
                                    HStack {
                                        Text(scene.metadata.name)
                                            .font(.body)

                                        Spacer()

                                        if scene.status?.active == "active" {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(scene.status?.active == "active" ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadRoomState()
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
        Task {
            do {
                try await HueAPIService.shared.activateScene(sceneId: scene.id)
                // Refresh room state
                await bridgeManager.refreshRoom(roomId: room.id)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to activate scene: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
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
