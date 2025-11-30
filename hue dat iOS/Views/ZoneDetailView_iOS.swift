//
//  ZoneDetailView_iOS.swift
//  hue dat iOS
//
//  Zone control view with native iOS controls
//

import SwiftUI
import HueDatShared

struct ZoneDetailView_iOS: View {
    let zoneId: String

    @EnvironmentObject var bridgeManager: BridgeManager

    @State private var isOn: Bool = false
    @State private var brightness: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isApplyingScene = false
    @State private var isViewActive = true

    // Optimistic state for immediate UI feedback
    @State private var optimisticIsOn: Bool?
    @State private var optimisticBrightness: Double?

    // Task tracking for cleanup
    @State private var brightnessTask: Task<Void, Never>?
    @State private var sceneTask: Task<Void, Never>?
    @State private var powerTask: Task<Void, Never>?
    @State private var sceneResetWorkItem: DispatchWorkItem?

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
        ZStack {
            // Background
            ColorOrbsBackground_iOS(
                brightness: displayBrightness,
                isOn: displayIsOn
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Controls section
                VStack(spacing: 24) {
                    Spacer()

                    // Brightness percentage display
                    Text("\(Int(displayBrightness))%")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 4)

                    Spacer()

                    // Power toggle button
                    Button(action: {
                        togglePower(!displayIsOn)
                    }) {
                        Image(systemName: displayIsOn ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 80))
                            .foregroundColor(displayIsOn ? .white : .gray)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Brightness slider
                    HStack(spacing: 16) {
                        Image(systemName: "sun.min")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.title2)

                        Slider(value: Binding(
                            get: { displayBrightness },
                            set: { newValue in
                                setBrightness(newValue)
                            }
                        ), in: 1...100)
                        .disabled(!displayIsOn)
                        .tint(.white)

                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.title2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .frame(height: 350)

                // Scenes section
                if !bridgeManager.scenes.filter({ $0.group.rid == zoneId }).isEmpty {
                    Divider()

                    ScrollView {
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
                        .padding()
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
        }
        .navigationTitle(zone?.metadata.name ?? "Unknown Zone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: iconForArchetype(zone?.metadata.archetype ?? ""))
                        .foregroundColor(.white)
                    Text(zone?.metadata.name ?? "Unknown Zone")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            isViewActive = true
            loadZoneState()
        }
        .onDisappear {
            isViewActive = false
            // Cancel any running tasks
            brightnessTask?.cancel()
            sceneTask?.cancel()
            powerTask?.cancel()
            sceneResetWorkItem?.cancel()
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

        // Cancel any existing power task
        powerTask?.cancel()

        // Optimistic update
        optimisticIsOn = newValue

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
                }
            } catch {
                // Rollback optimistic update only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
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

        // Cancel any existing scene task
        sceneTask?.cancel()

        // Optimistic updates - immediate UI feedback
        optimisticIsOn = true
        if let sceneBrightness = sceneBrightness {
            optimisticBrightness = sceneBrightness
        }

        sceneTask = Task {
            do {
                try await HueAPIService.shared.activateScene(sceneId: scene.id)

                // Update actual state after successful activation, only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
                await MainActor.run {
                    isOn = true
                    if let sceneBrightness = sceneBrightness {
                        // Set flag to prevent onChange from triggering API call
                        isApplyingScene = true
                        brightness = sceneBrightness

                        // Reset flag after brief delay
                        sceneResetWorkItem?.cancel()
                        let workItem = DispatchWorkItem {
                            guard isViewActive else { return }
                            isApplyingScene = false
                        }
                        sceneResetWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                    // Clear optimistic state
                    optimisticIsOn = nil
                    optimisticBrightness = nil
                }
            } catch {
                // Rollback optimistic updates on error, only if view is still active
                guard !Task.isCancelled, isViewActive else { return }
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
                .padding(.vertical, 8)
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.white.opacity(0.8) : Color.clear,
                        lineWidth: 2.5
                    )
            )
        }
        .buttonStyle(.plain)
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
        default: return "lightbulb.led.fill"
        }
    }
}
