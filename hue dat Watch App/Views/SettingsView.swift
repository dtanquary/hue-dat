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

    var body: some View {
        NavigationStack {
            List {
                // All Lights Off Section
                Section {
                    Button {
                        Task {
                            await turnOffAllLights()
                        }
                    } label: {
                        HStack {
                            Label("Turn Off All Lights", systemImage: "lightbulb.slash")
                            Spacer()
                            if isTurningOffLights {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTurningOffLights || bridgeManager.connectedBridge == nil)
                }

                // Bridge Connection Section
                Section("Bridge Connection") {
                    if let bridge = bridgeManager.connectedBridge {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("IP Address")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.bridge.internalipaddress)
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Bridge ID")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(bridge.bridge.id.prefix(8)))
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Connected")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.connectedDate, style: .date)
                                    .font(.caption)
                            }
                        }
                        .font(.caption)

                        Button(role: .destructive) {
                            showDisconnectAlert = true
                        } label: {
                            Label("Disconnect Bridge", systemImage: "xmark.circle")
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
