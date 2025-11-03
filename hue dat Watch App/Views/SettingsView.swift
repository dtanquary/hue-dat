//
//  SettingsView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 11/2/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var showDisconnectAlert = false
    @State private var isTurningOffLights = false
    @State private var hasGivenInitialHaptic = false
    @State private var hasGivenFinalHaptic = false
    @Environment(\.dismiss) private var dismiss

    // Dynamic Type scaled metrics
    @ScaledMetric(relativeTo: .caption) private var infoSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var labelIconSpacing: CGFloat = 6

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.slash")
                .font(.title3)

            VStack(alignment: .leading, spacing: 10) {
                Text("Turn Off All Lights")
                    .font(.headline)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        
        NavigationStack {
            List {
                // All Lights Off Section
                Section {
                    Button {
                        Task {
                            await turnOffAllLights()
                        }
                    } label: {
                        HStack(spacing: labelIconSpacing) {
                            Image(systemName: "lightbulb.slash")
                                .font(.body)
                                .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                            Text("Turn Off All Lights")
                                .font(.body)
                            Spacer()
                            if isTurningOffLights {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTurningOffLights || bridgeManager.connectedBridge == nil)
                    .glassEffect()
                }

                // Bridge Connection Section
                Section("Bridge Connection") {
                    if let bridge = bridgeManager.connectedBridge {
                        VStack(alignment: .leading, spacing: infoSpacing) {
                            HStack {
                                Text("IP Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.bridge.internalipaddress)
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Bridge ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(bridge.bridge.id.prefix(8)))
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.connectedDate, style: .date)
                                    .font(.caption)
                            }
                        }

                        Button(role: .destructive) {
                            showDisconnectAlert = true
                        } label: {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "xmark.circle")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Disconnect Bridge")
                                    .font(.body)
                            }
                        }
                    } else {
                        Text("No bridge connected")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    bridgeManager.disconnectBridge()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to disconnect? You'll need to set up the connection again.")
            }
        }
    }

    // MARK: - Actions

    private func turnOffAllLights() async {
        // Give initial haptic feedback
        if !hasGivenInitialHaptic {
            WKInterfaceDevice.current().play(.start)
            hasGivenInitialHaptic = true
        }

        isTurningOffLights = true

        let result = await bridgeManager.turnOffAllLights()

        switch result {
        case .success:
            // Give success haptic
            if !hasGivenFinalHaptic {
                WKInterfaceDevice.current().play(.success)
                hasGivenFinalHaptic = true
            }

        case .failure(let error):
            print("❌ Failed to turn off all lights: \(error.localizedDescription)")
            // Give failure haptic
            WKInterfaceDevice.current().play(.failure)
        }

        isTurningOffLights = false

        // Reset haptic flags after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hasGivenInitialHaptic = false
            hasGivenFinalHaptic = false
        }
    }
}
