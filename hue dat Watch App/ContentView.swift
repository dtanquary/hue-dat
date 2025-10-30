//
//  ContentView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var discoveryService = BridgeDiscoveryService()
    @StateObject private var bridgeManager = BridgeManager()
    @State private var showBridgesList = false
    @State private var showDisconnectAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Hue Bridge Discovery")
                        
                        Text("Hue Control")
                            .font(.title3.weight(.medium))
                    }
                    
                    // Main content
                    if let connectedBridge = bridgeManager.connectedBridge {
                        // Connected state
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Text(connectedBridge.bridge.displayName)
                                    .font(.headline)
                                
                                Text(connectedBridge.bridge.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("Connected \(connectedBridge.connectedDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                            
                            Button("Disconnect", role: .destructive) {
                                showDisconnectAlert = true
                            }
                            .accessibilityLabel("Disconnect from current bridge")
                            .glassEffect()
                        }
                    } else {
                        // Discovery state
                        VStack(spacing: 12) {
                            Button {
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
                                            .tint(.white)
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
                            .glassEffect()
                            
                            // Tappable bridge count
                            if !discoveryService.discoveredBridges.isEmpty && !discoveryService.isLoading {
                                Button {
                                    showBridgesList = true
                                } label: {
                                    Text("\(discoveryService.discoveredBridges.count) found")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show \(discoveryService.discoveredBridges.count) discovered bridge\(discoveryService.discoveredBridges.count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Hue Control")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showBridgesList, onDismiss: {
            // Cancel any ongoing discovery when sheet is dismissed
            if discoveryService.isLoading {
                discoveryService.cancelDiscovery()
            }
        }) {
            BridgesListView(bridges: discoveryService.discoveredBridges, bridgeManager: bridgeManager)
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
            }
        } message: {
            Text("Are you sure you want to disconnect? You'll need to set up the connection again.")
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
}

#Preview {
    ContentView()
}
