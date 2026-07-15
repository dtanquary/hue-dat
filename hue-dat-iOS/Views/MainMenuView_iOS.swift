//
//  MainMenuView_iOS.swift
//  hue dat iOS
//
//  Main menu for bridge discovery and connection
//

import SwiftUI
import HueDatShared

struct MainMenuView_iOS: View {
    @Environment(\.colorScheme) var colorScheme
    var bridgeManager: BridgeManager
    @State private var discoveryService = BridgeDiscoveryService()
    @State private var showBridgesList = false
    @State private var showManualEntry = false
    @State private var showRegistrationForManualBridge = false
    @State private var manualBridgeInfo: BridgeInfo?

    @Namespace var animation
    @State private var showAboutSheet = false

    var body: some View {
        // Show discovery UI immediately (ContentView only shows this when no bridge is connected)
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text("Control your Philips Hue lights")
                .font(.largeTitle.bold())
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .padding(.horizontal)

            Text("Add your Hue bridge to get started")
                .font(.title)
                .foregroundStyle(colorScheme == .dark ? .white : .black.opacity(0.75))
                .padding(.horizontal)
                .padding(.bottom, 24)

            Spacer()

            VStack{
                VStack(spacing: 16) {
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
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .symbolEffect(.rotate, isActive: discoveryService.isLoading)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(discoveryService.isLoading ? "Searching..." : "Search For Bridges")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .tint(.primary)
                        .font(.title3)
                        .glassEffect()
                        .matchedTransitionSource(id: "BridgeList", in: animation)
                    }
                    .disabled(discoveryService.isLoading)
                }
                VStack(spacing: 16) {
                    Button {
                        showManualEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Manually Add A Bridge")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .tint(.primary)
                        .font(.title3)
                        .glassEffect()
                        .matchedTransitionSource(id: "BridgeList", in: animation)
                    }
                    .disabled(discoveryService.isLoading)
                    .matchedTransitionSource(id: "BridgeManualEntry", in: animation)
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AnimatedMeshBackground()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar{
            ToolbarItem(placement: .topBarTrailing) {
                Button("About", systemImage: "info"){
                    showAboutSheet.toggle()
                }
                .matchedTransitionSource(id: "About", in: animation)
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView_iOS().navigationTransition(.zoom(sourceID: "About", in: animation))
        }
        .sheet(isPresented: $showBridgesList, onDismiss: {
            // Cancel any ongoing discovery when sheet is dismissed
            if discoveryService.isLoading {
                discoveryService.cancelDiscovery()
            }
        }) {
            BridgesListView_iOS(
                bridges: discoveryService.discoveredBridges,
                bridgeManager: bridgeManager,
                onManualEntryTapped: {
                    showBridgesList = false
                    showManualEntry = true
                }
            )
            .navigationTransition(.zoom(sourceID: "BridgeList", in: animation))
        }
        .sheet(isPresented: $showManualEntry) {
            ManualBridgeEntryView_iOS { bridgeInfo in
                manualBridgeInfo = bridgeInfo
                showRegistrationForManualBridge = true
            }
            .navigationTransition(.zoom(sourceID: "BridgeManualEntry", in: animation))
        }
        .sheet(isPresented: $showRegistrationForManualBridge) {
            if let bridge = manualBridgeInfo {
                BridgesListView_iOS(
                    bridges: [bridge],
                    bridgeManager: bridgeManager,
                    onManualEntryTapped: {
                        showRegistrationForManualBridge = false
                        showManualEntry = true
                    }
                )
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
            Button("Manually Add A Bridge") {
                showManualEntry = true
            }
            Button("Ok") { }
        } message: {
            Text("No Hue bridges could be found on your network. Make sure your bridge is connected and try again.")
        }
    }
}

// MARK: - Animated Mesh Background

/// Slow-drifting mesh gradient in Hue-ish colors. Replaces the old looping video background.
private struct AnimatedMeshBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: [Color] {
        if colorScheme == .dark {
            return [
                .black, .indigo, .black,
                .purple, Color(red: 0.15, green: 0.1, blue: 0.3), .teal,
                .black, Color(red: 0.8, green: 0.4, blue: 0.1), .black
            ]
        } else {
            return [
                .white, .indigo.opacity(0.4), .white,
                .purple.opacity(0.35), Color(red: 0.85, green: 0.8, blue: 0.95), .teal.opacity(0.4),
                .white, .orange.opacity(0.3), .white
            ]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate / 6
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [Float(0.5 + 0.2 * sin(t * 0.7)), 0], [1, 0],
                    [0, Float(0.5 + 0.2 * cos(t * 0.8))],
                    [Float(0.5 + 0.3 * sin(t)), Float(0.5 + 0.3 * cos(t * 0.9))],
                    [1, Float(0.5 + 0.2 * sin(t * 0.6))],
                    [0, 1], [Float(0.5 + 0.2 * cos(t * 0.5)), 1], [1, 1]
                ],
                colors: colors
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        MainMenuView_iOS(bridgeManager: BridgeManager())
    }
}
