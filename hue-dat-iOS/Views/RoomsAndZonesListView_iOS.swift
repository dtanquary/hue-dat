//
//  RoomsAndZonesListView_iOS.swift
//  hue dat iOS
//
//  Main list view displaying rooms and zones with real data from bridge
//

import SwiftUI
import HueDatShared
import Combine

struct RoomsAndZonesListView_iOS: View {
    var bridgeManager: BridgeManager
    @Binding var navigationPath: NavigationPath
    let zoomNamespace: Namespace.ID
    @State private var hasLoadedData = false
    @State private var showSettings = false
    @State private var showNetworkErrorAlert = false
    @State private var isTurningOffLights = false
    @State private var roomsCount = 0
    @State private var zonesCount = 0
    @State private var searchText = ""

    // Haptic triggers (counters so repeated events re-fire)
    @State private var toggleHapticCount = 0
    @State private var toggleErrorCount = 0
    @State private var refreshHapticCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var animation

    // Search functionality
    @State private var searchManager: SearchManager?
    @State private var toastMessage: String?
    @State private var showToast = false

    // SSE status tracking
    @State private var sseStreamState: StreamState = .idle
    @State private var sseStateCancellable: AnyCancellable?
    @State private var isReconnecting = false

    private var lastUpdateText: String {
        if let lastUpdate = bridgeManager.lastRefreshTimestamp {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Updated \(formatter.localizedString(for: lastUpdate, relativeTo: Date()))"
        }
        return ""
    }

    private var searchResults: SearchResults {
        searchManager?.search(searchText) ?? SearchResults(rooms: [], zones: [], scenes: [])
    }

    // MARK: - SSE Status Properties

    private var sseStatusColor: Color {
        switch sseStreamState {
        case .connected: return .green
        case .connecting: return .blue
        case .disconnected, .error: return .red
        case .idle: return .gray
        }
    }

    private var sseStatusText: String {
        switch sseStreamState {
        case .connected: return "SSE Connected"
        case .connecting: return "SSE Connecting..."
        case .disconnected: return "SSE Disconnected"
        case .error: return "SSE Connection Error"
        case .idle: return "SSE Not Started"
        }
    }

    private var sseStatusIcon: String {
        // Use antenna icon for all states - color will differentiate
        return "antenna.radiowaves.left.and.right"
    }

    private var showReconnectButton: Bool {
        switch sseStreamState {
        case .disconnected, .error, .idle: return true
        case .connected, .connecting: return false
        }
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
                .symbolEffect(.breathe, options: .repeat(.continuous), isActive: !reduceMotion)
            Text("No rooms or zones found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Refresh") {
                Task {
                    await refreshData(forceRefresh: true)
                }
            }
            .buttonStyle(.glass)
        }
        .padding()
    }

    @ViewBuilder
    private var listContentView: some View {
        List {
            if searchText.isEmpty {
                roomsAndZonesSections
            } else {
                searchResultsSections
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refreshData(forceRefresh: true)
            refreshHapticCount += 1
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: toggleHapticCount)
        .sensoryFeedback(.error, trigger: toggleErrorCount)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: refreshHapticCount)
    }

    @ViewBuilder
    private var roomsAndZonesSections: some View {
        let isLoading = bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones

        // Rooms section
        if !bridgeManager.rooms.isEmpty {
            Section {
                ForEach(bridgeManager.rooms) { room in
                    groupRow(for: room, isLoading: isLoading)
                        .disabled(isLoading)
                }
            } header: {
                sectionHeader("ROOMS", count: roomsCount)
            }
            .id("rooms-section")
        }

        // Zones section
        if !bridgeManager.zones.isEmpty {
            Section {
                ForEach(bridgeManager.zones) { zone in
                    groupRow(for: zone, isLoading: isLoading)
                        .disabled(isLoading)
                }
            } header: {
                sectionHeader("ZONES", count: zonesCount)
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

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSections: some View {
        let results = searchResults

        if results.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No results for '\(searchText)'")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } else {
            if !results.rooms.isEmpty {
                Section {
                    ForEach(results.rooms) { room in
                        groupRow(for: room, isLoading: false)
                    }
                } header: {
                    sectionHeader("ROOMS", count: results.rooms.count)
                }
            }

            if !results.zones.isEmpty {
                Section {
                    ForEach(results.zones) { zone in
                        groupRow(for: zone, isLoading: false)
                    }
                } header: {
                    sectionHeader("ZONES", count: results.zones.count)
                }
            }

            if !results.scenes.isEmpty {
                Section {
                    ForEach(results.scenes, id: \.scene.id) { sceneResult in
                        sceneResultRow(sceneResult)
                    }
                } header: {
                    sectionHeader("SCENES", count: results.scenes.count)
                }
            }
        }
    }

    private func groupRow<G: GroupedLightContainer>(for group: G, isLoading: Bool) -> some View {
        Button {
            navigationPath.append(group)
        } label: {
            GroupRowView_iOS(group: group, isLoading: isLoading) {
                togglePower(for: group)
            }
        }
        .buttonStyle(PressableRowStyle())
        .matchedTransitionSource(id: group.id, in: zoomNamespace)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func togglePower<G: GroupedLightContainer>(for group: G) {
        guard let lightId = group.services?.first(where: { $0.rtype == "grouped_light" })?.rid,
              let light = group.groupedLights?.first else { return }
        let oldValue = light.on?.on ?? false
        let newValue = !oldValue
        toggleHapticCount += 1

        // Optimistic update: rows render straight from bridgeManager.rooms/zones,
        // SSE echo confirms (no post-action refresh, per project convention)
        if G.isRoom {
            bridgeManager.updateLocalRoomState(roomId: group.id, on: newValue)
        } else {
            bridgeManager.updateLocalZoneState(zoneId: group.id, on: newValue)
        }

        Task {
            let result = await bridgeManager.setGroupedLightPower(id: lightId, on: newValue)
            if case .failure = result {
                if G.isRoom {
                    bridgeManager.updateLocalRoomState(roomId: group.id, on: oldValue)
                } else {
                    bridgeManager.updateLocalZoneState(zoneId: group.id, on: oldValue)
                }
                toggleErrorCount += 1
                toastMessage = "Couldn't toggle \(group.metadata.name)"
                withAnimation {
                    showToast = true
                }
            }
        }
    }

    private func sceneResultRow(_ sceneResult: SceneSearchResult) -> some View {
        Button {
            activateScene(sceneResult)
        } label: {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HighlightedText(
                        text: sceneResult.scene.metadata.name,
                        highlight: searchText
                    )
                    .foregroundStyle(.primary)

                    if let context = sceneResult.contextDescription {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
    }

    var body: some View {
        contentWithNavigation
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView_iOS(bridgeManager: bridgeManager)
                }.navigationTransition(.zoom(sourceID: "Settings", in: animation))
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
                // Initialize SearchManager
                if searchManager == nil {
                    searchManager = SearchManager(bridgeManager: bridgeManager)
                }

                // Subscribe to SSE state changes
                subscribeToSSEState()

                // Set initial SSE state
                if bridgeManager.isSSEConnected {
                    sseStreamState = .connected
                }

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
                    debugLog("🔄 New bridge detected, resetting view state and loading fresh data")
                    hasLoadedData = false
                    // The .task modifier will trigger automatically when hasLoadedData changes
                }
            }
    }

    @ViewBuilder
    private var contentWithNavigation: some View {
        mainContent
            .navigationTitle("Rooms & Zones")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Rooms, Zones, and Scenes")
            .toolbar {
                toolbarContent
            }
            .opacity((bridgeManager.isRefreshing && !hasLoadedData) ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: bridgeManager.isRefreshing)
            .overlay {
                loadingOverlay
            }
            .toast(isShowing: $showToast, message: toastMessage ?? "")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // SSE Status Menu
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                // Status display with colored antenna icon
                Label {
                    Text(sseStatusText)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: sseStatusIcon)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(sseStatusColor)
                }

                // Explanatory caption
                Text("Real-time updates from your Hue Bridge")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Reconnect button (only when disconnected)
                if showReconnectButton {
                    Divider()
                    Button {
                        reconnectSSE()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    .disabled(isReconnecting || sseStreamState == .connecting)
                }
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(sseStatusColor)
            }
        }.sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                PinnedScenesListView { scene, groupId in
                    activateSceneFromPinned(scene, groupId: groupId)
                }
                .environment(bridgeManager)
            } label: {
                Image(systemName: "pin.fill")
            }
        }

        ToolbarSpacer(placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task {
                        await turnOffAllLights()
                    }
                } label: {
                    Label("Turn off all lights", systemImage: "moon.fill")
                }
                .disabled(isTurningOffLights || bridgeManager.connectedBridge == nil)

                Button {
                    Task {
                        await refreshData(forceRefresh: true)
                    }
                } label: {
                    Label("Refresh Data", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: bridgeManager.isRefreshing)

                }
                .disabled(bridgeManager.isRefreshing || bridgeManager.connectedBridge == nil)

                Button("Settings", systemImage: "gear"){
                    showSettings = true
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .matchedTransitionSource(id: "Settings", in: animation)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if bridgeManager.isRefreshing && !hasLoadedData {
            LoadingCard(message: "Loading rooms & zones...")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func refreshData(forceRefresh: Bool) async {
        // Fetch rooms, zones, and scenes in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await bridgeManager.getRooms(forceRefresh: forceRefresh)
            }
            group.addTask {
                await bridgeManager.getZones(forceRefresh: forceRefresh)
            }
            group.addTask {
                await bridgeManager.fetchScenes()
            }
        }

        hasLoadedData = true
    }

    private func turnOffAllLights() async {
        isTurningOffLights = true

        let result = await bridgeManager.turnOffAllLights()

        switch result {
        case .success:
            debugLog("✅ All lights turned off successfully")

        case .failure(let error):
            debugLog("❌ Failed to turn off all lights: \(error.localizedDescription)")
        }

        isTurningOffLights = false
    }

    // MARK: - SSE Status Functions

    private func subscribeToSSEState() {
        Task {
            guard bridgeManager.connectedBridge != nil else { return }
            let service = HueAPIService.shared
            let streamSubject = await service.streamStateSubject

            await MainActor.run {
                sseStateCancellable = streamSubject
                    .receive(on: DispatchQueue.main)
                    .sink { state in
                        sseStreamState = state
                        if state == .connected {
                            isReconnecting = false
                        }
                    }
            }
        }
    }

    private func reconnectSSE() {
        isReconnecting = true
        Task {
            await bridgeManager.reconnectSSE()
            // State will be updated via subscription
        }
    }

    // MARK: - Scene Activation

    private func activateScene(_ sceneResult: SceneSearchResult) {
        Task { @MainActor in
            do {
                try await HueAPIService.shared.activateScene(
                    sceneId: sceneResult.scene.id
                )

                // Success - show toast and close search
                toastMessage = "Scene '\(sceneResult.scene.metadata.name)' applied"
                withAnimation {
                    showToast = true
                    searchText = ""
                }
            } catch {
                // Error - show error alert, keep search open
                showNetworkErrorAlert = true
                bridgeManager.refreshError = "Failed to activate scene: \(error.localizedDescription)"
            }
        }
    }

    private func activateSceneFromPinned(_ scene: HueScene, groupId: String) {
        Task { @MainActor in
            do {
                try await HueAPIService.shared.activateScene(
                    sceneId: scene.id
                )

                // Success - show toast
                toastMessage = "Scene '\(scene.metadata.name)' applied"
                withAnimation {
                    showToast = true
                }
            } catch {
                // Error - show error alert
                showNetworkErrorAlert = true
                bridgeManager.refreshError = "Failed to activate scene: \(error.localizedDescription)"
            }
        }
    }
}

/// Scales the whole row down slightly while pressed (3% is interaction
/// feedback, not ambient motion — no reduce-motion gate needed).
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    @Previewable @Namespace var namespace

    NavigationStack(path: $path) {
        RoomsAndZonesListView_iOS(
            bridgeManager: BridgeManager(),
            navigationPath: $path,
            zoomNamespace: namespace
        )
    }
}
