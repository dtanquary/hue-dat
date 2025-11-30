//
//  BridgeSetupView_macOS.swift
//  hue dat macOS
//
//  Bridge discovery and setup for macOS
//

import SwiftUI
import HueDatShared

struct BridgeSetupView_macOS: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bridgeManager: BridgeManager

    @StateObject private var discoveryService = BridgeDiscoveryService()
    @StateObject private var registrationService: BridgeRegistrationService

    @State private var showManualEntry = false

    init() {
        _registrationService = StateObject(wrappedValue: BridgeRegistrationService(
            deviceIdentifierProvider: MacOSDeviceIdentifierProvider()
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connect to Hue Bridge")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            if discoveryService.isLoading {
                loadingView
            } else if discoveryService.discoveredBridges.isEmpty {
                noBridgesView
            } else {
                bridgesListView
            }
        }
        .frame(width: 500, height: 400)
        .task {
            await discoveryService.discoverBridges()
        }
        .alert("Success", isPresented: .constant(registrationService.successfulBridge != nil)) {
            Button("OK") {
                if let bridge = registrationService.successfulBridge,
                   let response = registrationService.registrationResponse {
                    bridgeManager.saveConnection(bridge: bridge, registrationResponse: response)
                    registrationService.clearSuccess()
                    dismiss()
                }
            }
        } message: {
            if let bridge = registrationService.successfulBridge {
                Text("Successfully connected to \(bridge.displayName)")
            }
        }
        .alert("Press Link Button", isPresented: $registrationService.showLinkButtonAlert) {
            Button("Retry") {
                if let bridge = registrationService.linkButtonBridge {
                    Task {
                        await registrationService.registerWithBridge(bridge)
                    }
                }
            }
            Button("Cancel") {
                registrationService.clearLinkButtonAlert()
            }
        } message: {
            Text("Press the link button on your Hue bridge, then click Retry.")
        }
        .alert("Error", isPresented: .constant(registrationService.error != nil)) {
            Button("OK") {
                registrationService.error = nil
            }
        } message: {
            if let error = registrationService.error {
                Text(error.localizedDescription)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching for Hue bridges...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noBridgesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("No Bridges Found")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Make sure your Hue bridge is connected to the same network as this Mac.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Retry") {
                    // Set loading state immediately for instant UI feedback
                    discoveryService.isLoading = true

                    Task {
                        await discoveryService.discoverBridges()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Add Manually") {
                    showManualEntry = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var bridgesListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found \(discoveryService.discoveredBridges.count) bridge(s)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List(discoveryService.discoveredBridges) { bridge in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bridge.displayName)
                            .font(.body)
                            .fontWeight(.medium)

                        Text(bridge.displayAddress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if registrationService.isRegistering(bridge: bridge) {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if registrationService.isRegistered(bridge: bridge) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Connect") {
                            Task {
                                await registrationService.registerWithBridge(bridge)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(registrationService.hasActiveRegistration)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button("Add Bridge Manually") {
                    showManualEntry = true
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)

                Spacer()

                Button("Refresh") {
                    // Set loading state immediately for instant UI feedback
                    discoveryService.isLoading = true

                    Task {
                        await discoveryService.discoverBridges()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    BridgeSetupView_macOS()
        .environmentObject(BridgeManager())
}
