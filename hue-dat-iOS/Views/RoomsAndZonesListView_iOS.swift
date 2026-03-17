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
    @State private var hasLoadedData = false
    @State private var showSettings = false
    @State private var showNetworkErrorAlert = false
    @State private var isTurningOffLights = false
    @State private var roomsCount = 0
    @State private var zonesCount = 0
    @State private var loadingStep = 0
    @State private var loadingMessage = ""
    @State private var searchText = ""

    enum FocusedField {
        case search
    }
    @FocusState private var focusedField: FocusedField?

    @Namespace var animation

    // Search functionality
    @State private var showSearchOverlay = false
    @State private var searchManager: SearchManager?
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var searchResults = SearchResults(rooms: [], zones: [], scenes: [])

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
        let isLoading = bridgeManager.isLoadingRooms || bridgeManager.isLoadingZones

        List {
            // Rooms section
            if !bridgeManager.rooms.isEmpty {
                Section {
                    ForEach(bridgeManager.rooms) { room in
                        ZStack {
                            NavigationLink(value: room) {
                                EmptyView()
                            }
                            .opacity(0)

                            GroupRowView_iOS(group: room, isLoading: isLoading)
                        }
                        .disabled(isLoading)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("ROOMS (\(roomsCount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 0)
                }
                .id("rooms-section")
            }

            // Zones section
            if !bridgeManager.zones.isEmpty {
                Section {
                    ForEach(bridgeManager.zones) { zone in
                        ZStack {
                            NavigationLink(value: zone) {
                                EmptyView()
                            }
                            .opacity(0)

                            GroupRowView_iOS(group: zone, isLoading: isLoading)
                        }
                        .disabled(isLoading)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("ZONES (\(zonesCount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
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
            .onChange(of: focusedField) { _, newField in
                let isFocused = newField == .search
                withAnimation {
                    showSearchOverlay = isFocused
                }
                if isFocused {
                    searchResults = performSearch()
                }
            }
            .onChange(of: searchText) { _, newText in
                // Update search results
                searchResults = performSearch()

                // Show overlay if field is focused OR there's text
                if focusedField == .search || !newText.isEmpty {
                    withAnimation {
                        showSearchOverlay = true
                    }
                }
            }
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
            .toolbar {
                toolbarContent
            }
            .toolbar {
                if (!bridgeManager.rooms.isEmpty || !bridgeManager.zones.isEmpty)
                    && hasLoadedData {
                    searchToolbarContent
                }
            }
            .opacity((bridgeManager.isRefreshing && !hasLoadedData) ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: bridgeManager.isRefreshing)
            .overlay {
                ZStack {
                    loadingOverlay

                    if showSearchOverlay {
                        SearchResultsOverlay(
                            searchResults: searchResults,
                            searchQuery: searchText,
                            onRoomTap: navigateToRoom,
                            onZoneTap: navigateToZone,
                            onSceneTap: activateScene
                        )
                        .transition(.opacity)
                        .zIndex(100)
                    }
                }
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
    
    @ToolbarContentBuilder
    private var searchToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            searchBarView
        }
        if (showSearchOverlay) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Close", systemImage: "xmark"){
                    focusedField = nil
                    searchText = ""
                    withAnimation {
                        showSearchOverlay = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 12) {
            // Search field container
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Rooms, Zones, and Scenes", text: $searchText)
                    .focused($focusedField, equals: .search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    // MARK: - Search Functions

    private func performSearch() -> SearchResults {
        guard let searchManager = searchManager else {
            return SearchResults(rooms: [], zones: [], scenes: [])
        }
        return searchManager.search(searchText)
    }

    // MARK: - Navigation Handlers

    private func navigateToRoom(_ room: HueRoom) {
        // Close search
        searchText = ""
        focusedField = nil
        withAnimation {
            showSearchOverlay = false
        }

        // Note: Navigation will be handled by ContentView's navigationDestination
        // We'll use a Notification to trigger navigation
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToRoom"),
            object: nil,
            userInfo: ["room": room]
        )
    }

    private func navigateToZone(_ zone: HueZone) {
        // Close search
        searchText = ""
        focusedField = nil
        withAnimation {
            showSearchOverlay = false
        }

        // Note: Navigation will be handled by ContentView's navigationDestination
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToZone"),
            object: nil,
            userInfo: ["zone": zone]
        )
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
                    // CONFIGURABLE: Set this to false to keep search open
                    let closeSearchOnSuccess = true
                    if closeSearchOnSuccess {
                        searchText = ""
                        focusedField = nil
                        showSearchOverlay = false
                    }
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

#Preview {
    NavigationStack {
        RoomsAndZonesListView_iOS(bridgeManager: BridgeManager())
    }
}
