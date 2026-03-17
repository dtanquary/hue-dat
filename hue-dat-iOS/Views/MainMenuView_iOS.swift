//
//  MainMenuView_iOS.swift
//  hue dat iOS
//
//  Main menu for bridge discovery and connection
//

import SwiftUI
import HueDatShared
import AVKit
import AVFoundation

struct MainMenuView_iOS: View {
    @Environment(\.colorScheme) var colorScheme
    var bridgeManager: BridgeManager
    @State private var discoveryService = BridgeDiscoveryService()
    @State private var showBridgesList = false
    @State private var showManualEntry = false
    @State private var showRegistrationForManualBridge = false
    @State private var manualBridgeInfo: BridgeInfo?
    
    @State private var playerLooper: AVPlayerLooper?
    @State private var player = AVQueuePlayer()
    @State private var isVideoSetup = false
    @State private var isViewActive = true
    
    @Namespace var animation
    @State private var showAboutSheet = false
    
    @Environment(\.scenePhase) private var scenePhase

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
            backgroundView
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
        .task {
            debugLog("MainMenuView task started")
            isViewActive = true
            await setupVideoAsync()
        }
        .onAppear {
            debugLog("MainMenuView appeared")
            isViewActive = true
            // Resume playback if already setup
            if isVideoSetup && player.rate == 0 {
                player.play()
            }
        }
        .onDisappear {
            debugLog("MainMenuView disappeared")
            isViewActive = false
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
                LoopingVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .opacity(1)
            }
            
            // Background Color
            if (colorScheme == .dark) {
                Color.black
                    .ignoresSafeArea()
                    .opacity(0.3)
            } else {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.6)
            }
        }
    }

    private func setupVideoAsync() async {
        guard !isVideoSetup else {
            debugLog("Video already setup")
            return
        }

        debugLog("Setting up video async...")

        // Load video from asset catalog
        let videoURL = await MainActor.run {
            let videoName = colorScheme == .light ? "light-lightTheme" : "light"
            return LoopingVideoPlayer.loadVideoURL(named: videoName)
        }

        guard let videoURL = videoURL else {
            debugLog("❌ Failed to load video URL")
            return
        }
        debugLog("✅ Video URL loaded: \(videoURL)")

        await MainActor.run {
            // Configure audio session to mix with other audio (e.g., Music)
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                debugLog("✅ Audio session configured for ambient playback")
            } catch {
                debugLog("⚠️ Failed to configure audio session: \(error)")
            }

            let playerItem = AVPlayerItem(url: videoURL)

            // Configure player
            player.isMuted = true
            player.allowsExternalPlayback = false

            // Setup looping
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            debugLog("✅ Player looper setup complete")

            // Mark as setup and start playing if view is active
            isVideoSetup = true
            if isViewActive {
                player.play()
                debugLog("✅ Player started")
            }
        }
    }
}

#Preview {
    NavigationStack {
        MainMenuView_iOS(bridgeManager: BridgeManager())
    }
}
