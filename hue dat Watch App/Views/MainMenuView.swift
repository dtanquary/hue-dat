//
//  MainMenuView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI
import HueDatShared
import AVFoundation
import AVKit

struct MainMenuView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @StateObject private var discoveryService = BridgeDiscoveryService()
    @State private var showBridgesList = false
    @State private var showManualEntry = false
    @State private var showRegistrationForManualBridge = false
    @State private var manualBridgeInfo: BridgeInfo?

    // Video player state
    @State private var player = AVPlayer()
    @State private var isVideoSetup = false
    @State private var isViewActive = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if bridgeManager.connectedBridge != nil {
                // Connected - ContentView will handle navigation to RoomsAndZonesListView
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(3.0)
                }
                .navigationTitle("Hue Control")
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
                            .glassEffect()

                            /*
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
                                .accessibilityLabel("Show \(discoveryService.discoveredBridges.count) discovered bridge\(discoveryService.discoveredBridges.count == 1 ? "" : "s")")
                            }
                             */
                        }
                    }
                    .padding()
                }
                .background {
                    backgroundView
                }
                .navigationTitle("Hue Control")
                .navigationBarTitleDisplayMode(.automatic)
                .task {
                    isViewActive = true
                    await setupVideoAsync()
                }
                .onAppear {
                    isViewActive = true
                    // Resume playback if already setup
                    if isVideoSetup && player.rate == 0 {
                        player.play()
                    }
                }
                .onDisappear {
                    isViewActive = false
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        player.play()
                    case .background, .inactive:
                        player.pause()
                    @unknown default:
                        break
                    }
                }
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
        ZStack {
            // Fallback gradient background (shows immediately)
            LinearGradient(
                colors: [Color.primary, Color.blue.opacity(0.3), Color.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Video overlay if available
            if isVideoSetup {
                LoopingVideoPlayer_watchOS(player: player)
                    .ignoresSafeArea()
                    .opacity(1)
            }

            // Dark overlay for button readability
            Color.black
                .ignoresSafeArea()
                .opacity(0.3)
        }
    }

    // MARK: - Video Setup

    private func setupVideoAsync() async {
        guard !isVideoSetup else { return }

        // Load video from asset catalog
        let videoURL = await MainActor.run {
            LoopingVideoPlayer_watchOS.loadVideoURL(named: "light")
        }

        guard let videoURL = videoURL else {
            print("❌ Failed to load video URL")
            return
        }

        await MainActor.run {
            let playerItem = AVPlayerItem(url: videoURL)

            // Configure player - completely silent to avoid audio interference
            player.isMuted = true
            player.volume = 0.0 // Extra safety - ensure no audio
            player.replaceCurrentItem(with: playerItem)

            // Setup manual looping using notification (AVPlayerLooper not available on watchOS)
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }

            // Mark as setup and start playing immediately
            isVideoSetup = true

            // Start playing automatically
            player.play()
            print("✅ Video player started")
        }
    }
}
