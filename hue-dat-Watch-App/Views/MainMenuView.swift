//
//  MainMenuView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI
import HueDatShared

struct MainMenuView: View {
    var bridgeManager: BridgeManager
    @State private var discoveryService = BridgeDiscoveryService()
    @State private var showBridgesList = false
    @State private var showManualEntry = false
    @State private var showRegistrationForManualBridge = false
    @State private var manualBridgeInfo: BridgeInfo?

    var body: some View {
        Group {
            if bridgeManager.connectedBridge != nil {
                // Connected - ContentView will handle navigation to RoomsAndZonesListView
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(3.0)
                }
                .navigationTitle("Firefly")
                .navigationBarTitleDisplayMode(.automatic)
            } else {
                // Not connected - show discovery
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Button {
                                // Set loading state immediately for instant UI feedback
                                discoveryService.isLoading = true

                                Task {
                                    await discoveryService.discoverBridges()
                                    if !discoveryService.discoveredBridges.isEmpty {
                                        showBridgesList = true
                                    }
                                }
                            } label: {
                                HStack {
                                    if discoveryService.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    Text(discoveryService.isLoading ? "Searching..." : "Find Bridges")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .disabled(discoveryService.isLoading)
                            .accessibilityLabel("Discover Hue bridges on network")
                            .buttonStyle(.glassProminent)
                            
                            Button {
                                showManualEntry = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Manually Add Bridge")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .disabled(discoveryService.isLoading)
                            .accessibilityLabel("Manually add a Hue bridge on your network")
                            .buttonStyle(.glass)
                        }
                    }
                    .padding()
                }
                .background {
                    backgroundView
                }
                .navigationTitle("Firefly")
                .navigationBarTitleDisplayMode(.automatic)
            }
        }
        .sheet(isPresented: $showBridgesList, onDismiss: {
            // Cancel any ongoing discovery when sheet is dismissed
            if discoveryService.isLoading {
                discoveryService.cancelDiscovery()
            }
        }) {
            BridgesListView(bridges: discoveryService.discoveredBridges, bridgeManager: bridgeManager)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualBridgeEntryView { bridgeInfo in
                manualBridgeInfo = bridgeInfo
                showRegistrationForManualBridge = true
            }
        }
        .sheet(isPresented: $showRegistrationForManualBridge) {
            if let bridge = manualBridgeInfo {
                BridgesListView(bridges: [bridge], bridgeManager: bridgeManager)
            }
        }
        .alert("Discovery Error", isPresented: Binding(
            get: { discoveryService.error != nil },
            set: { if !$0 { discoveryService.error = nil } }
        )) {
            Button("OK") {
                discoveryService.error = nil
            }
        } message: {
            if let error = discoveryService.error {
                Text("Failed to discover bridges: \(error.localizedDescription)")
            }
        }
        .alert("No Bridges Found", isPresented: $discoveryService.showNoBridgesAlert) {
            Button("OK") { }
        } message: {
            Text("No Hue bridges could be found on your network. Make sure your bridge is connected and try again.")
        }
    }

    // MARK: - Background View

    private var backgroundView: some View {
        ColorOrbsBackground(brightness: 60, isOn: true)
            .ignoresSafeArea()
    }
}
