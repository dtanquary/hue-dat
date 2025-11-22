//
//  RoomsAndZonesListView_iOS.swift
//  hue dat iOS
//
//  Main list view displaying rooms and zones with real data from bridge
//

import SwiftUI
import HueDatShared

struct RoomsAndZonesListView_iOS: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var hasLoadedData = false
    @State private var showSettings = false
    @State private var showNetworkErrorAlert = false
    @State private var isTurningOffLights = false
    @State private var roomsCount = 0
    @State private var zonesCount = 0
    @State private var loadingStep = 0
    @State private var loadingMessage = ""

    private var lastUpdateText: String {
        if let lastUpdate = bridgeManager.lastRefreshTimestamp {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Updated \(formatter.localizedString(for: lastUpdate, relativeTo: Date()))"
        }
        return ""
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty && !bridgeManager.isRefreshing && hasLoadedData {
                emptyStateView
            } else {
                listContentView
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.3.layers.3d.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No rooms or zones found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Refresh") {
                Task {
                    await refreshData(forceRefresh: true)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    @ViewBuilder
    private var listContentView: some View {
        List {
            // Rooms section
            if !bridgeManager.rooms.isEmpty {
                Section {
                    ForEach(bridgeManager.rooms) { room in
                        NavigationLink {
                            RoomDetailView_iOS(roomId: room.id)
                                .environmentObject(bridgeManager)
                        } label: {
                            RoomRowView(room: room)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("ROOMS (\(roomsCount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.leading, 0)
                }
                .id("rooms-section")
            }

            // Zones section
            if !bridgeManager.zones.isEmpty {
                Section {
                    ForEach(bridgeManager.zones) { zone in
                        NavigationLink {
                            ZoneDetailView_iOS(zoneId: zone.id)
                                .environmentObject(bridgeManager)
                        } label: {
                            ZoneRowView(zone: zone)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("ZONES (\(zonesCount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.leading, 0)
                }
                .id("zones-section")
            }

            // Last update timestamp
            if !lastUpdateText.isEmpty {
                Section {
                    Text(lastUpdateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refreshData(forceRefresh: true)
        }
    }


    var body: some View {
        contentWithNavigation
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView_iOS(bridgeManager: bridgeManager)
                }
            }
            .alert("Network Error", isPresented: $showNetworkErrorAlert) {
                Button("OK", role: .cancel) {}
                Button("Retry") {
                    Task {
                        await refreshData(forceRefresh: true)
                    }
                }
            } message: {
                if let error = bridgeManager.refreshError {
                    Text(error)
                } else {
                    Text("Unable to refresh room and zone data. Please check your connection.")
                }
            }
            .task {
                // Initialize counts
                roomsCount = bridgeManager.rooms.count
                zonesCount = bridgeManager.zones.count

                // Load data once when view appears (if empty)
                if bridgeManager.rooms.isEmpty && bridgeManager.zones.isEmpty {
                    await refreshData(forceRefresh: false)
                }
                hasLoadedData = true

                // Start periodic refresh after initial load
                bridgeManager.startPeriodicRefresh()
            }
            .onChange(of: bridgeManager.rooms) { _, newRooms in
                roomsCount = newRooms.count
            }
            .onChange(of: bridgeManager.zones) { _, newZones in
                zonesCount = newZones.count
            }
            .onChange(of: bridgeManager.refreshError) { _, newError in
                // Only show alert if error occurs and we've attempted to load data
                if newError != nil && hasLoadedData {
                    showNetworkErrorAlert = true
                }
            }
            .onChange(of: bridgeManager.connectedBridge) { oldBridge, newBridge in
                // When bridge connection changes, reset state and reload
                if let newBridge = newBridge, oldBridge?.bridge.id != newBridge.bridge.id {
                    print("🔄 New bridge detected, resetting view state and loading fresh data")
                    hasLoadedData = false
                    // The .task modifier will trigger automatically when hasLoadedData changes
                }
            }
    }

    @ViewBuilder
    private var contentWithNavigation: some View {
        mainContent
            .navigationTitle("Rooms & Zones")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                toolbarContent
            }
            .opacity((bridgeManager.isRefreshing && !hasLoadedData) ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: bridgeManager.isRefreshing)
            .overlay {
                loadingOverlay
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SSEStatusIndicator(bridgeManager: bridgeManager)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    await turnOffAllLights()
                }
            } label: {
                if isTurningOffLights {
                    ProgressView()
                } else {
                    Image(systemName: "moon")
                }
            }
            .disabled(isTurningOffLights || bridgeManager.connectedBridge == nil)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    await refreshData(forceRefresh: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: bridgeManager.isRefreshing)
                    
            }
            .disabled(bridgeManager.isRefreshing)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if bridgeManager.isRefreshing && !hasLoadedData {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                LoadingStepIndicator(
                    currentStep: max(1, loadingStep),
                    totalSteps: 4,
                    message: loadingMessage.isEmpty ? "Preparing..." : loadingMessage
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .animation(.easeInOut(duration: 0.3), value: loadingStep)
        }
    }

    private func refreshData(forceRefresh: Bool) async {
        // Reset loading state
        loadingStep = 1
        loadingMessage = "Preparing..."

        // Use TaskGroup to track progress of parallel operations
        await withTaskGroup(of: String.self) { group in
            // Add all three tasks
            group.addTask {
                await bridgeManager.getRooms(forceRefresh: forceRefresh)
                return "rooms"
            }
            group.addTask {
                await bridgeManager.getZones(forceRefresh: forceRefresh)
                return "zones"
            }
            group.addTask {
                await bridgeManager.fetchScenes()
                return "scenes"
            }

            // Track completion of each task
            var completedCount = 0
            for await completed in group {
                completedCount += 1

                // Update UI based on which task completed
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        loadingStep = completedCount + 1
                        switch completed {
                        case "rooms":
                            loadingMessage = "Loaded rooms..."
                        case "zones":
                            loadingMessage = "Loaded zones..."
                        case "scenes":
                            loadingMessage = "Loaded scenes..."
                        default:
                            break
                        }

                        // Show final message when all complete
                        if completedCount == 3 {
                            loadingMessage = "Finishing up..."
                        }
                    }
                }
            }
        }

        hasLoadedData = true
    }

    private func turnOffAllLights() async {
        isTurningOffLights = true

        let result = await bridgeManager.turnOffAllLights()

        switch result {
        case .success:
            print("✅ All lights turned off successfully")

        case .failure(let error):
            print("❌ Failed to turn off all lights: \(error.localizedDescription)")
        }

        isTurningOffLights = false
    }
}

#Preview {
    NavigationStack {
        RoomsAndZonesListView_iOS(bridgeManager: BridgeManager())
    }
}
