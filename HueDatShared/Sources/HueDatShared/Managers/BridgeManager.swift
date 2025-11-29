//
//  BridgeManager.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Connection Validation Result
public enum ConnectionValidationResult {
    case success
    case failure(message: String)
}

// MARK: - Bridge Manager
@MainActor
public class BridgeManager: ObservableObject {
    @Published public var connectedBridge: BridgeConnectionInfo?
    @Published public var showAlert: Bool = false
    @Published public var alertMessage: String? = nil
    @Published public var isConnectionValidated: Bool = false
    @Published public var rooms: [HueRoom] = []
    @Published public var zones: [HueZone] = []
    @Published public var scenes: [HueScene] = []
    @Published public var isLoadingRooms: Bool = false
    @Published public var isLoadingZones: Bool = false
    @Published public var refreshError: String? = nil  // Error message for background refresh failures
    @Published public var isDemoMode: Bool = false  // Demo mode flag for offline demonstration
    @Published public var isRefreshing: Bool = false  // Combined refresh state for UI feedback

    // Event broadcasting for connection validation
    private let connectionValidationSubject = PassthroughSubject<ConnectionValidationResult, Never>()
    public var connectionValidationPublisher: AnyPublisher<ConnectionValidationResult, Never> {
        connectionValidationSubject.eraseToAnyPublisher()
    }

    // SSE event handling
    private var eventSubscription: AnyCancellable?
    private var streamStateSubscription: AnyCancellable?
    @Published public var isSSEConnected: Bool = false
    public var reconnectAttempts = 0  // Public so ContentView can reset on successful connection
    private let maxReconnectAttempts = 5

    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    private let cachedRoomsKey = "CachedRooms"
    private let cachedZonesKey = "CachedZones"
    private let cachedScenesKey = "CachedScenes"
    private let demoModeKey = "DemoMode"

    // Refresh state management (concurrent call protection)
    private var isRefreshingRooms: Bool = false
    private var isRefreshingZones: Bool = false

    // Debouncing (prevent refresh spam during rapid navigation)
    private var lastRoomsRefreshTime: Date? = nil
    private var lastZonesRefreshTime: Date? = nil
    private let refreshDebounceInterval: TimeInterval = 30.0  // 30 seconds

    // Periodic refresh
    private var refreshTimer: Timer?
    @Published public var lastRefreshTimestamp: Date?


    /// Returns the current connected bridge information, or nil if none is connected.
    public var currentConnectedBridge: BridgeConnectionInfo? {
        connectedBridge
    }
    
    public init() {
        loadConnectedBridge()
        loadDemoModeState()
        // Clean up old lights cache (migration)
        if userDefaults.object(forKey: "CachedLights") != nil {
            userDefaults.removeObject(forKey: "CachedLights")
            print("🧹 Cleaned up old lights cache")
        }
        loadRoomsFromStorage()
        loadZonesFromStorage()
        loadScenesFromStorage()
    }
    
    public func saveConnection(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        // Validate bridge IP is not localhost (prevent data corruption)
        if bridge.internalipaddress == "127.0.0.1" ||
           bridge.internalipaddress == "localhost" ||
           bridge.internalipaddress == "::1" {
            print("❌ Refusing to save bridge with localhost IP: \(bridge.internalipaddress)")
            print("  - Bridge must be on local network (e.g., 192.168.x.x or 10.0.x.x)")
            return
        }

        let connectionInfo = BridgeConnectionInfo(bridge: bridge, registrationResponse: registrationResponse)

        do {
            let data = try JSONEncoder().encode(connectionInfo)
            userDefaults.set(data, forKey: connectedBridgeKey)

            // Force synchronize to ensure data is written immediately
            userDefaults.synchronize()

            connectedBridge = connectionInfo
            print("✅ Bridge connection saved successfully:")
            print("  - Bridge: \(bridge.displayName) (\(bridge.shortId))")
            print("  - IP Address: \(bridge.internalipaddress)")
            print("  - Username: \(registrationResponse.username)")
            print("  - ClientKey: \(registrationResponse.clientkey ?? "nil")")
            print("  - Connected Date: \(connectionInfo.connectedDate)")
            print("  - Data size: \(data.count) bytes")
            
            // Verify the save by immediately reading it back
            if let verifyData = userDefaults.data(forKey: connectedBridgeKey) {
                print("✅ Verification: Data successfully retrieved from UserDefaults (\(verifyData.count) bytes)")
            } else {
                print("❌ Verification failed: Could not retrieve data from UserDefaults")
            }
        } catch {
            print("❌ Failed to save bridge connection: \(error)")
        }
    }
    
    public func disconnectBridge() {
        userDefaults.removeObject(forKey: connectedBridgeKey)
        userDefaults.removeObject(forKey: cachedRoomsKey)
        userDefaults.removeObject(forKey: cachedZonesKey)
        userDefaults.removeObject(forKey: cachedScenesKey)
        userDefaults.synchronize()
        connectedBridge = nil
        isConnectionValidated = false
        rooms = []
        zones = []
        scenes = []
        print("🔌 Bridge disconnected and cleared from storage")
    }

    // MARK: - Demo Mode Management

    /// Load demo mode state from UserDefaults
    private func loadDemoModeState() {
        isDemoMode = userDefaults.bool(forKey: demoModeKey)
        if isDemoMode {
            print("🎭 Demo mode is ENABLED")
        }
    }

    /// Enable demo mode for offline demonstration
    public func enableDemoMode() {
        isDemoMode = true
        userDefaults.set(true, forKey: demoModeKey)
        userDefaults.synchronize()
        print("🎭 Demo mode ENABLED")
    }

    /// Disable demo mode and return to normal operation
    public func disableDemoMode() {
        isDemoMode = false
        userDefaults.set(false, forKey: demoModeKey)
        userDefaults.synchronize()
        print("🎭 Demo mode DISABLED")
    }

    /// Get demo data - uses cached data if available, otherwise returns hardcoded demo data
    private func getDemoRooms() -> [HueRoom] {
        // If we have cached rooms, use those for demo
        if !rooms.isEmpty {
            return rooms
        }

        // Otherwise load from storage if available
        if let data = userDefaults.data(forKey: cachedRoomsKey),
           let cachedRooms = try? JSONDecoder().decode([HueRoom].self, from: data),
           !cachedRooms.isEmpty {
            return cachedRooms
        }

        // Fallback to hardcoded demo data
        return createHardcodedDemoRooms()
    }

    private func getDemoZones() -> [HueZone] {
        // If we have cached zones, use those for demo
        if !zones.isEmpty {
            return zones
        }

        // Otherwise load from storage if available
        if let data = userDefaults.data(forKey: cachedZonesKey),
           let cachedZones = try? JSONDecoder().decode([HueZone].self, from: data),
           !cachedZones.isEmpty {
            return cachedZones
        }

        // Fallback to hardcoded demo data
        return createHardcodedDemoZones()
    }

    private func getDemoScenes() -> [HueScene] {
        // If we have cached scenes, use those for demo
        if !scenes.isEmpty {
            return scenes
        }

        // Otherwise load from storage if available
        if let data = userDefaults.data(forKey: cachedScenesKey),
           let cachedScenes = try? JSONDecoder().decode([HueScene].self, from: data),
           !cachedScenes.isEmpty {
            return cachedScenes
        }

        // Fallback to hardcoded demo data
        return []
    }

    /// Create hardcoded demo rooms for initial demo when no cache exists
    private func createHardcodedDemoRooms() -> [HueRoom] {
        let demoGroupedLight = HueGroupedLight(
            id: "demo-grouped-light-1",
            type: "grouped_light",
            on: HueGroupedLight.GroupedLightOn(on: true),
            dimming: HueGroupedLight.GroupedLightDimming(brightness: 75.0),
            color_temperature: nil,
            color: HueGroupedLight.GroupedLightColor(
                xy: HueGroupedLight.GroupedLightColor.GroupedLightColorXY(x: 0.4573, y: 0.41),
                gamut: nil,
                gamut_type: nil
            )
        )

        return [
            HueRoom(
                id: "demo-room-1",
                type: "room",
                metadata: HueRoom.RoomMetadata(name: "Living Room", archetype: "living_room"),
                children: nil,
                services: [HueRoom.HueRoomService(rid: "demo-grouped-light-1", rtype: "grouped_light")],
                groupedLights: [demoGroupedLight]
            ),
            HueRoom(
                id: "demo-room-2",
                type: "room",
                metadata: HueRoom.RoomMetadata(name: "Bedroom", archetype: "bedroom"),
                children: nil,
                services: [HueRoom.HueRoomService(rid: "demo-grouped-light-2", rtype: "grouped_light")],
                groupedLights: [HueGroupedLight(
                    id: "demo-grouped-light-2",
                    type: "grouped_light",
                    on: HueGroupedLight.GroupedLightOn(on: false),
                    dimming: HueGroupedLight.GroupedLightDimming(brightness: 50.0),
                    color_temperature: HueGroupedLight.GroupedLightColorTemperature(mirek: 366, mirek_valid: true, mirek_schema: nil),
                    color: nil
                )]
            ),
            HueRoom(
                id: "demo-room-3",
                type: "room",
                metadata: HueRoom.RoomMetadata(name: "Kitchen", archetype: "kitchen"),
                children: nil,
                services: [HueRoom.HueRoomService(rid: "demo-grouped-light-3", rtype: "grouped_light")],
                groupedLights: [HueGroupedLight(
                    id: "demo-grouped-light-3",
                    type: "grouped_light",
                    on: HueGroupedLight.GroupedLightOn(on: true),
                    dimming: HueGroupedLight.GroupedLightDimming(brightness: 100.0),
                    color_temperature: HueGroupedLight.GroupedLightColorTemperature(mirek: 250, mirek_valid: true, mirek_schema: nil),
                    color: nil
                )]
            )
        ]
    }

    /// Create hardcoded demo zones for initial demo when no cache exists
    private func createHardcodedDemoZones() -> [HueZone] {
        return [
            HueZone(
                id: "demo-zone-1",
                type: "zone",
                metadata: HueZone.ZoneMetadata(name: "Downstairs", archetype: "home"),
                children: nil,
                services: [HueZone.HueZoneService(rid: "demo-zone-light-1", rtype: "grouped_light")],
                groupedLights: [HueGroupedLight(
                    id: "demo-zone-light-1",
                    type: "grouped_light",
                    on: HueGroupedLight.GroupedLightOn(on: true),
                    dimming: HueGroupedLight.GroupedLightDimming(brightness: 80.0),
                    color_temperature: nil,
                    color: nil
                )]
            )
        ]
    }

    // MARK: - SSE Event Processing

    /// Maps grouped_light ID to room ID for fast lookup
    private var groupedLightToRoomMap: [String: String] {
        var map: [String: String] = [:]
        for room in rooms {
            if let services = room.services,
               let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                map[groupedLightService.rid] = room.id
            }
        }
        return map
    }

    /// Maps grouped_light ID to zone ID for fast lookup
    private var groupedLightToZoneMap: [String: String] {
        var map: [String: String] = [:]
        for zone in zones {
            if let services = zone.services,
               let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                map[groupedLightService.rid] = zone.id
            }
        }
        return map
    }

    /// Start listening to SSE events from HueAPIService
    public func startListeningToSSEEvents() {
        // Demo mode: Skip SSE event listening
        if isDemoMode {
            print("🎭 startListeningToSSEEvents: Demo mode - skipping SSE")
            return
        }

        // Prevent duplicate subscriptions
        if eventSubscription != nil && streamStateSubscription != nil {
            print("⚠️ SSE event listeners already running - skipping duplicate start")
            return
        }

        print("📡 Starting SSE event listener")

        // Cancel any existing subscriptions first to prevent memory leaks
        eventSubscription?.cancel()
        streamStateSubscription?.cancel()

        // Use Task to access actor-isolated properties
        Task {
            let service = HueAPIService.shared

            // Subscribe to event publisher using Combine
            await MainActor.run {
                eventSubscription = service.eventPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] events in
                        guard let self = self else { return }
                        Task {
                            await self.processSSEEvents(events)
                        }
                    }

                // Subscribe to stream state changes using Combine
                streamStateSubscription = service.streamStateSubject
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] state in
                        guard let self = self else { return }

                        // Update connection status
                        self.isSSEConnected = (state == .connected)

                        // Handle disconnections with auto-reconnect
                        if case .disconnected = state, self.reconnectAttempts < self.maxReconnectAttempts {
                            Task {
                                await self.handleReconnection()
                            }
                        }
                    }
            }
        }
    }

    /// Stop listening to SSE events
    public func stopListeningToSSEEvents() {
        print("🛑 Stopping SSE event listener")
        eventSubscription?.cancel()
        streamStateSubscription?.cancel()
        eventSubscription = nil
        streamStateSubscription = nil
        isSSEConnected = false
        reconnectAttempts = 0  // Reset reconnection counter
    }

    /// Manually reconnect SSE stream (for user-initiated reconnection)
    public func reconnectSSE() async {
        // Only reconnect if we have a connected bridge
        guard isConnected else {
            print("⚠️ Cannot reconnect SSE - no bridge connected")
            return
        }

        // Don't reconnect if already connected
        if isSSEConnected {
            print("ℹ️ SSE already connected - skipping reconnection")
            return
        }

        print("🔄 Manually reconnecting SSE stream...")

        // Stop existing connection if any
        stopListeningToSSEEvents()

        // Reset reconnection counter for fresh attempts
        reconnectAttempts = 0

        // Start fresh connection
        startListeningToSSEEvents()

        // Trigger the actual stream start
        do {
            try await HueAPIService.shared.startEventStream()
            print("✅ SSE stream reconnected successfully")
        } catch {
            print("❌ Failed to reconnect SSE stream: \(error.localizedDescription)")
        }
    }

    /// Process incoming SSE events and update local state
    private func processSSEEvents(_ events: [SSEEvent]) async {
        let relevantUpdates = events.relevantUpdates

        guard !relevantUpdates.isEmpty else { return }

        print("🔄 Processing \(relevantUpdates.count) relevant event(s)")

        for eventData in relevantUpdates {
            switch eventData.resourceType {
            case .groupedLight:
                await handleGroupedLightUpdate(eventData)
            case .room:
                await handleRoomUpdate(eventData)
            case .zone:
                await handleZoneUpdate(eventData)
            case .scene:
                await handleSceneUpdate(eventData)
            default:
                break
            }
        }
    }

    /// Handle grouped_light update event
    private func handleGroupedLightUpdate(_ data: SSEEventData) async {
        print("💡 Grouped light update: \(data.debugDescription)")

        let groupedLightId = data.id

        // Check if this grouped light belongs to a room
        if let roomId = groupedLightToRoomMap[groupedLightId] {
            // Extract state changes
            let on = data.on?.on
            let brightness = data.dimming?.brightness

            // Update local room state
            await MainActor.run {
                updateLocalRoomState(roomId: roomId, on: on, brightness: brightness)
            }
            print("  ✓ Updated room \(roomId)")
        }

        // Check if this grouped light belongs to a zone
        if let zoneId = groupedLightToZoneMap[groupedLightId] {
            // Extract state changes
            let on = data.on?.on
            let brightness = data.dimming?.brightness

            // Update local zone state
            await MainActor.run {
                updateLocalZoneState(zoneId: zoneId, on: on, brightness: brightness)
            }
            print("  ✓ Updated zone \(zoneId)")
        }
    }

    /// Handle room metadata update event
    private func handleRoomUpdate(_ data: SSEEventData) async {
        print("🏠 Room update: \(data.debugDescription)")

        let roomId = data.id

        // Check if we need to update metadata
        if let metadata = data.metadata, let name = metadata.name {
            await MainActor.run {
                if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                    var updatedRoom = rooms[index]
                    // Create new metadata with updated values
                    let archetype = metadata.archetype ?? updatedRoom.metadata.archetype
                    updatedRoom.metadata = HueRoom.RoomMetadata(name: name, archetype: archetype)
                    rooms[index] = updatedRoom
                    print("  ✓ Updated room '\(name)' metadata")
                }
            }
        }
    }

    /// Handle zone metadata update event
    private func handleZoneUpdate(_ data: SSEEventData) async {
        print("🗺️ Zone update: \(data.debugDescription)")

        let zoneId = data.id

        // Check if we need to update metadata
        if let metadata = data.metadata, let name = metadata.name {
            await MainActor.run {
                if let index = zones.firstIndex(where: { $0.id == zoneId }) {
                    var updatedZone = zones[index]
                    // Create new metadata with updated values
                    let archetype = metadata.archetype ?? updatedZone.metadata.archetype
                    updatedZone.metadata = HueZone.ZoneMetadata(name: name, archetype: archetype)
                    zones[index] = updatedZone
                    print("  ✓ Updated zone '\(name)' metadata")
                }
            }
        }
    }

    /// Handle scene status update event
    private func handleSceneUpdate(_ data: SSEEventData) async {
        print("🎬 Scene update: \(data.debugDescription)")

        // Log scene activation/deactivation for debugging
        if let status = data.status?.active {
            print("  ✓ Scene \(data.id.prefix(8)) is now: \(status)")
        }
    }

    /// Handle auto-reconnection with exponential backoff
    private func handleReconnection() async {
        // Don't attempt reconnection if we're in demo mode or not connected to a bridge
        if isDemoMode || connectedBridge == nil {
            print("⚠️ Skipping SSE reconnection - no active bridge connection")
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 32.0) // 1s, 2s, 4s, 8s, 16s, 32s max

        print("🔄 SSE disconnected. Reconnecting in \(Int(delay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Check again before reconnecting (bridge might have been disconnected during sleep)
        guard connectedBridge != nil else {
            print("⚠️ Bridge disconnected during reconnection delay - aborting")
            return
        }

        // Restart the SSE stream
        do {
            try await HueAPIService.shared.startEventStream()
            print("✅ SSE stream reconnected")
            await MainActor.run {
                reconnectAttempts = 0  // Reset on success
            }
        } catch {
            print("❌ Failed to reconnect SSE stream: \(error)")
            // Don't retry here - the stream state subscription will trigger another reconnection attempt
        }
    }

    private func loadConnectedBridge() {
        print("🔍 Loading bridge connection from UserDefaults...")
        
        guard let data = userDefaults.data(forKey: connectedBridgeKey) else {
            print("❌ No saved bridge connection found")
            return
        }
        
        print("📊 Found saved data: \(data.count) bytes")
        
        do {
            connectedBridge = try JSONDecoder().decode(BridgeConnectionInfo.self, from: data)
            if let connection = connectedBridge {
                print("✅ Loaded saved bridge connection:")
                print("  - Bridge: \(connection.bridge.shortId)")
                print("  - Address: \(connection.bridge.displayAddress)")
                print("  - Internal IP: \(connection.bridge.internalipaddress)")
                print("  - Username: \(connection.username)")
                print("  - ClientKey: \(connection.clientkey ?? "nil")")
                print("  - Connected Date: \(connection.connectedDate)")

                // Validate that the bridge IP is not localhost (corrupted data)
                if connection.bridge.internalipaddress == "127.0.0.1" ||
                   connection.bridge.internalipaddress == "localhost" ||
                   connection.bridge.internalipaddress == "::1" {
                    print("❌ Invalid bridge IP detected (localhost) - clearing corrupted connection")
                    userDefaults.removeObject(forKey: connectedBridgeKey)
                    userDefaults.synchronize()
                    connectedBridge = nil
                    isConnectionValidated = false
                    print("🧹 Cleared localhost connection - please re-discover your bridge")
                }
            }
        } catch {
            print("❌ Failed to load bridge connection: \(error)")
            print("  - Error details: \(error.localizedDescription)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: connectedBridgeKey)
            userDefaults.synchronize()
            isConnectionValidated = false
            print("🧹 Cleaned up corrupted data")
        }
    }

    // MARK: - Rooms and Zones Persistence

    private func loadRoomsFromStorage() {
        guard let data = userDefaults.data(forKey: cachedRoomsKey) else {
            print("📂 No cached rooms found")
            return
        }

        do {
            rooms = try JSONDecoder().decode([HueRoom].self, from: data)
            print("✅ Loaded \(rooms.count) cached rooms from storage")
        } catch {
            print("❌ Failed to load cached rooms: \(error)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedRoomsKey)
        }
    }

    private func saveRoomsToStorage() {
        do {
            let data = try JSONEncoder().encode(rooms)
            userDefaults.set(data, forKey: cachedRoomsKey)
            print("💾 Saved \(rooms.count) rooms to storage (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save rooms to storage: \(error)")
        }
    }

    private func loadZonesFromStorage() {
        guard let data = userDefaults.data(forKey: cachedZonesKey) else {
            print("📂 No cached zones found")
            return
        }

        do {
            zones = try JSONDecoder().decode([HueZone].self, from: data)
            print("✅ Loaded \(zones.count) cached zones from storage")
        } catch {
            print("❌ Failed to load cached zones: \(error)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedZonesKey)
        }
    }

    private func saveZonesToStorage() {
        do {
            let data = try JSONEncoder().encode(zones)
            userDefaults.set(data, forKey: cachedZonesKey)
            print("💾 Saved \(zones.count) zones to storage (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save zones to storage: \(error)")
        }
    }

    private func loadScenesFromStorage() {
        guard let data = userDefaults.data(forKey: cachedScenesKey) else {
            print("📂 No cached scenes found")
            return
        }

        do {
            scenes = try JSONDecoder().decode([HueScene].self, from: data)
            print("✅ Loaded \(scenes.count) cached scenes from storage")
        } catch {
            print("❌ Failed to load cached scenes: \(error)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedScenesKey)
        }
    }

    private func saveScenesToStorage() {
        do {
            let data = try JSONEncoder().encode(scenes)
            userDefaults.set(data, forKey: cachedScenesKey)
            print("💾 Saved \(scenes.count) scenes to storage (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save scenes to storage: \(error)")
        }
    }

    /*
    // MARK: - Hue API Response Models
    private struct HueAPIV2Response: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueAPIV2Data]
    }
    
    private struct HueAPIV2Error: Decodable {
        let description: String
    }
    
    private struct HueAPIV2Data: Decodable {
        // The data array can contain various resource types
        // For validation purposes, we just need to know if data is present
    }
    
    // MARK: - Room API Response Models
    private struct HueRoomsResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueRoom]
    }
    
    // MARK: - Individual Room Response Models
    private struct HueRoomDetailResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueRoomDetail]
    }
    
    private struct HueRoomDetail: Decodable {
        let id: String
        let type: String
        let metadata: HueRoom.RoomMetadata
        let children: [HueRoom.HueRoomChild]?
        let services: [HueRoom.HueRoomService]?
    }
    
    // MARK: - Grouped Light API Response Models
    private struct HueGroupedLightResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueGroupedLight]
    }


    // MARK: - Individual Light API Response Models
    private struct HueLightResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueLight]
    }
    
    // MARK: - Zone API Response Models
    private struct HueZonesResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueZone]
    }
    

    // MARK: - Light API Response Models
    private struct HueLightsResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueLight]
    }

    // MARK: - Device API Response Models
    private struct HueDeviceResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueDevice]
    }
     */

    public var isConnected: Bool {
        connectedBridge != nil
    }

    /// Validate that the current connection is alive/reachable.
    /// Broadcasts the result via connectionValidationPublisher.
    public func validateConnection() async {
        // Demo mode: Skip validation and return success
        if isDemoMode {
            print("🎭 validateConnection: Demo mode - skipping validation")
            isConnectionValidated = true
            connectionValidationSubject.send(.success)
            return
        }

        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ validateConnection: No connected bridge available")
            isConnectionValidated = false
            connectionValidationSubject.send(.failure(message: "No bridge connection available"))
            return
        }
        isConnectionValidated = false

        // Setup HueAPIService with current bridge info
        await HueAPIService.shared.setup(
            baseUrl: bridge.internalipaddress,
            hueApplicationKey: currentConnectedBridge?.username ?? ""
        )

        do {
            _ = try await HueAPIService.shared.validateConnection()
            print("✅ validateConnection: Success")
            self.isConnectionValidated = true
            connectionValidationSubject.send(.success)
        } catch {
            print("❌ validateConnection: Error: \(error.localizedDescription)")
            self.isConnectionValidated = false
            self.alertMessage = error.localizedDescription
            self.showAlert = true
            connectionValidationSubject.send(.failure(message: error.localizedDescription))
        }
    }
    
    /// Retrieve the list of rooms from the connected bridge.
    /// Updates the rooms published property with the results.
    /// - Parameter forceRefresh: If true, bypasses debounce timer (for manual user-initiated refreshes)
    public func getRooms(forceRefresh: Bool = false) async {
        // Demo mode: Return cached/demo data
        if isDemoMode {
            print("🎭 getRooms: Demo mode - returning demo data")
            let demoRooms = getDemoRooms()
            self.rooms = demoRooms
            print("🎭 getRooms: Loaded \(demoRooms.count) demo rooms")
            return
        }

        // PROTECTION 1: Concurrent call protection
        guard !isRefreshingRooms else {
            print("⏭️ getRooms: Already refreshing rooms, skipping duplicate call")
            return
        }

        // PROTECTION 2: Debouncing - skip if refreshed recently (unless forced)
        if !forceRefresh {
            if let lastRefresh = lastRoomsRefreshTime,
               Date().timeIntervalSince(lastRefresh) < refreshDebounceInterval {
                let timeRemaining = refreshDebounceInterval - Date().timeIntervalSince(lastRefresh)
                print("⏭️ getRooms: Debounced - last refresh was \(Int(Date().timeIntervalSince(lastRefresh)))s ago, waiting \(Int(timeRemaining))s")
                return
            }
        } else {
            print("🔓 getRooms: Force refresh - bypassing debounce")
        }

        // Set loading state immediately
        isLoadingRooms = true
        isRefreshing = true

        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ getRooms: No connected bridge available")
            // PROTECTION 3: Only clear if no existing data
            if rooms.isEmpty {
                rooms = []
            }
            // Always reset loading flags
            isLoadingRooms = false
            updateCombinedRefreshState()
            return
        }

        isRefreshingRooms = true
        lastRoomsRefreshTime = Date()

        let delegate = InsecureURLSessionDelegate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0  // 10 second timeout for local network
        config.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        print("🏠 getRooms: Requesting rooms from bridge")

        do {
            // Fetch basic rooms list (without enrichment)
            let response = try await HueAPIService.shared.fetchRooms()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                print("❌ getRooms: Hue API v2 errors: \(errorMessages)")
                // PROTECTION 3: Keep existing data, set error instead
                refreshError = "API Error: \(errorMessages)"
                isLoadingRooms = false
                isRefreshingRooms = false
                updateCombinedRefreshState()  // Update combined state
                return
            }

            print("✅ getRooms: Success - retrieved \(response.data.count) rooms")

            // Enrich rooms with grouped light status
            var enrichedRooms = response.data
            for (index, room) in enrichedRooms.enumerated() {
                if let services = room.services,
                   let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                    if let groupedLight = await fetchGroupedLight(groupedLightId: groupedLightService.rid) {
                        enrichedRooms[index].groupedLights = [groupedLight]
                        print("  ✓ Enriched room '\(room.metadata.name)' with grouped light status (brightness: \(groupedLight.dimming?.brightness ?? 0)%)")
                    }
                }
            }

            self.rooms = enrichedRooms
            saveRoomsToStorage()  // Cache successful refresh
            refreshError = nil  // Clear any previous errors
            print("🏠 getRooms: Completed with \(enrichedRooms.count) rooms")

        } catch {
            print("❌ getRooms: Error: \(error.localizedDescription)")
            // PROTECTION 3: Keep existing data on error
            refreshError = "Error: \(error.localizedDescription)"
        }

        isLoadingRooms = false
        isRefreshingRooms = false
        updateCombinedRefreshState()  // Update combined state
    }

    /// Refresh a single room by fetching its latest data from the bridge.
    /// Updates only the specified room in the rooms array.
    public func refreshRoom(roomId: String) async {
        // Simplified: just refresh all rooms since the API is fast
        await getRooms()
    }

    /// Retrieve the list of zones from the connected bridge.
    /// Updates the zones published property with the results.
    /// - Parameter forceRefresh: If true, bypasses debounce timer (for manual user-initiated refreshes)
    public func getZones(forceRefresh: Bool = false) async {
        // Demo mode: Return cached/demo data
        if isDemoMode {
            print("🎭 getZones: Demo mode - returning demo data")
            let demoZones = getDemoZones()
            self.zones = demoZones
            print("🎭 getZones: Loaded \(demoZones.count) demo zones")
            return
        }

        // PROTECTION 1: Concurrent call protection
        guard !isRefreshingZones else {
            print("⏭️ getZones: Already refreshing zones, skipping duplicate call")
            return
        }

        // PROTECTION 2: Debouncing - skip if refreshed recently (unless forced)
        if !forceRefresh {
            if let lastRefresh = lastZonesRefreshTime,
               Date().timeIntervalSince(lastRefresh) < refreshDebounceInterval {
                let timeRemaining = refreshDebounceInterval - Date().timeIntervalSince(lastRefresh)
                print("⏭️ getZones: Debounced - last refresh was \(Int(Date().timeIntervalSince(lastRefresh)))s ago, waiting \(Int(timeRemaining))s")
                return
            }
        } else {
            print("🔓 getZones: Force refresh - bypassing debounce")
        }

        // Set loading state immediately
        isLoadingZones = true
        isRefreshing = true

        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ getZones: No connected bridge available")
            // PROTECTION 3: Only clear if no existing data
            if zones.isEmpty {
                zones = []
            }
            // Always reset loading flags
            isLoadingZones = false
            updateCombinedRefreshState()
            return
        }

        isRefreshingZones = true
        lastZonesRefreshTime = Date()

        let delegate = InsecureURLSessionDelegate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0  // 10 second timeout for local network
        config.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        print("🏢 getZones: Requesting zones from bridge")

        do {
            // Fetch basic zones list (without enrichment)
            let response = try await HueAPIService.shared.fetchZones()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                print("❌ getZones: Hue API v2 errors: \(errorMessages)")
                // PROTECTION 3: Keep existing data, set error instead
                refreshError = "API Error: \(errorMessages)"
                isLoadingZones = false
                isRefreshingZones = false
                updateCombinedRefreshState()  // Update combined state
                return
            }

            print("✅ getZones: Success - retrieved \(response.data.count) zones")

            // Enrich zones with grouped light status
            var enrichedZones = response.data
            for (index, zone) in enrichedZones.enumerated() {
                if let services = zone.services,
                   let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                    if let groupedLight = await fetchGroupedLight(groupedLightId: groupedLightService.rid) {
                        enrichedZones[index].groupedLights = [groupedLight]
                        print("  ✓ Enriched zone '\(zone.metadata.name)' with grouped light status (brightness: \(groupedLight.dimming?.brightness ?? 0)%)")
                    }
                }
            }

            self.zones = enrichedZones
            saveZonesToStorage()  // Cache successful refresh
            refreshError = nil  // Clear any previous errors
            print("🏢 getZones: Completed with \(enrichedZones.count) zones")

        } catch {
            print("❌ getZones: Error: \(error.localizedDescription)")
            // PROTECTION 3: Keep existing data on error
            refreshError = "Error: \(error.localizedDescription)"
        }

        isLoadingZones = false
        isRefreshingZones = false
        updateCombinedRefreshState()  // Update combined state
    }

    /// Refresh a single zone by fetching its latest data from the bridge.
    /// Updates only the specified zone in the zones array.
    public func refreshZone(zoneId: String) async {
        // Simplified: just refresh all zones since the API is fast
        await getZones()
    }

    // MARK: - Color Conversion Utilities

    /// Convert CIE XY color space to RGB
    /// Uses simplified conversion algorithm suitable for visual effects
    func xyToRGB(x: Double, y: Double, brightness: Double) -> Color {
        // Clamp values to valid ranges
        let x = max(0.0, min(1.0, x))
        let y = max(0.0, min(1.0, y))
        let brightness = max(0.0, min(100.0, brightness)) / 100.0

        // Avoid division by zero
        guard y > 0.0001 else {
            // Default to white if Y is too small
            return Color(red: brightness, green: brightness, blue: brightness)
        }

        // Calculate XYZ from xy
        let z = 1.0 - x - y
        let Y = brightness
        let X = (Y / y) * x
        let Z = (Y / y) * z

        // Convert XYZ to RGB using simplified sRGB matrix
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530

        // Apply gamma correction (simplified)
        r = r <= 0.0031308 ? 12.92 * r : (1.0 + 0.055) * pow(r, (1.0 / 2.4)) - 0.055
        g = g <= 0.0031308 ? 12.92 * g : (1.0 + 0.055) * pow(g, (1.0 / 2.4)) - 0.055
        b = b <= 0.0031308 ? 12.92 * b : (1.0 + 0.055) * pow(b, (1.0 / 2.4)) - 0.055

        // Clamp to valid RGB range
        r = max(0.0, min(1.0, r))
        g = max(0.0, min(1.0, g))
        b = max(0.0, min(1.0, b))

        return Color(red: r, green: g, blue: b)
    }

    /// Convert color temperature (mirek) to RGB
    /// Mirek = 1,000,000 / Kelvin
    func mirekToRGB(mirek: Int, brightness: Double) -> Color {
        // Convert mirek to Kelvin
        let kelvin = 1_000_000.0 / Double(mirek)
        let brightness = max(0.0, min(100.0, brightness)) / 100.0

        // Simplified color temperature to RGB
        // Based on approximate blackbody radiation
        var r: Double, g: Double, b: Double

        // Red calculation
        if kelvin <= 6600 {
            r = 1.0
        } else {
            let temp = kelvin / 100.0 - 60.0
            r = 329.698727446 * pow(temp, -0.1332047592)
            r = max(0.0, min(255.0, r)) / 255.0
        }

        // Green calculation
        if kelvin <= 6600 {
            let temp = kelvin / 100.0
            g = 99.4708025861 * log(temp) - 161.1195681661
            g = max(0.0, min(255.0, g)) / 255.0
        } else {
            let temp = kelvin / 100.0 - 60.0
            g = 288.1221695283 * pow(temp, -0.0755148492)
            g = max(0.0, min(255.0, g)) / 255.0
        }

        // Blue calculation
        if kelvin >= 6600 {
            b = 1.0
        } else if kelvin <= 1900 {
            b = 0.0
        } else {
            let temp = kelvin / 100.0 - 10.0
            b = 138.5177312231 * log(temp) - 305.0447927307
            b = max(0.0, min(255.0, b)) / 255.0
        }

        // Apply brightness
        r = r * brightness
        g = g * brightness
        b = b * brightness

        return Color(red: r, green: g, blue: b)
    }

    /// Extract a displayable color from a HueLight
    /// Returns nil if light should be hidden (off and user chose to hide)

    /// Update the combined isRefreshing state based on individual room/zone refresh states
    private func updateCombinedRefreshState() {
        isRefreshing = isRefreshingRooms || isRefreshingZones
    }

    // MARK: - Background Refresh Management

    /// Refresh all rooms, zones, and scenes data
    /// Now uses getRooms(), getZones(), and fetchScenes() which have built-in protections
    /// - Parameter forceRefresh: If true, bypasses debounce timer (for manual user-initiated refreshes)
    public func refreshAllData(forceRefresh: Bool = false) async {
        print("🔄 Refreshing all data (rooms, zones, scenes) \(forceRefresh ? "[FORCED]" : "")")

        // Use the protected getRooms(), getZones(), and fetchScenes() functions which have:
        // - Concurrent call protection
        // - Debouncing (unless forceRefresh is true)
        // - Data preservation on error
        async let roomsRefresh: Void = getRooms(forceRefresh: forceRefresh)
        async let zonesRefresh: Void = getZones(forceRefresh: forceRefresh)
        async let scenesRefresh: Void = fetchScenes()

        // Wait for all three to complete
        _ = await (roomsRefresh, zonesRefresh, scenesRefresh)

        // Update timestamp after successful refresh
        lastRefreshTimestamp = Date()
        print("✅ Refresh completed at \(lastRefreshTimestamp!)")

        // Check SSE connection status and attempt reconnection if needed
        if !isSSEConnected && isConnected {
            print("🔌 SSE not connected after refresh - attempting reconnection")
            startListeningToSSEEvents()

            // Trigger the actual stream start
            Task {
                do {
                    try await HueAPIService.shared.startEventStream()
                    print("✅ SSE stream restarted successfully")
                } catch {
                    print("❌ Failed to restart SSE stream: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Start periodic background refresh (every 60 seconds)
    public func startPeriodicRefresh() {
        // Check if timer is already running - prevent duplicate timers
        if refreshTimer != nil {
            print("⏭️ Periodic refresh already running, skipping duplicate start")
            return
        }

        print("⏰ Starting periodic refresh (60 second interval)")

        // Create timer that fires every 60 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                await self.refreshAllData()
            }
        }

        // Also trigger an immediate refresh
        Task {
            await refreshAllData()
        }
    }

    /// Stop periodic background refresh
    public func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("⏹️ Stopped periodic refresh")
    }

    /// Refresh rooms data using smart update logic
    private func refreshRoomsData() async {
        guard let bridge = currentConnectedBridge?.bridge else { return }

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/room"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(HueRoomsResponse.self, from: data)

            guard response.errors.isEmpty else { return }

            // Rooms from API already include children and services
            // Smart update - merge with existing data
            smartUpdateRooms(with: response.data)

        } catch {
            print("❌ refreshRoomsData: \(error.localizedDescription)")
        }
    }

    /// Refresh zones data using smart update logic
    private func refreshZonesData() async {
        guard let bridge = currentConnectedBridge?.bridge else { return }

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/zone"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(HueZonesResponse.self, from: data)

            guard response.errors.isEmpty else { return }

            // Zones from API already include children and services
            // Smart update - merge with existing data
            smartUpdateZones(with: response.data)

        } catch {
            print("❌ refreshZonesData: \(error.localizedDescription)")
        }
    }

    /// Smart update rooms array - only update changed items to minimize UI flicker
    private func smartUpdateRooms(with newRooms: [HueRoom]) {
        var updatedArray = rooms

        for newRoom in newRooms {
            if let index = updatedArray.firstIndex(where: { $0.id == newRoom.id }) {
                // Update existing room only if data has changed
                if !areRoomsEqual(updatedArray[index], newRoom) {
                    updatedArray[index] = newRoom
                }
            } else {
                // New room - append it
                updatedArray.append(newRoom)
            }
        }

        // Remove rooms that no longer exist
        updatedArray.removeAll { existingRoom in
            !newRooms.contains { $0.id == existingRoom.id }
        }

        rooms = updatedArray
        saveRoomsToStorage()
    }

    /// Update a single room in the array without affecting other rooms
    private func updateSingleRoom(_ room: HueRoom) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            // Update existing room only if data has changed
            if !areRoomsEqual(rooms[index], room) {
                rooms[index] = room
                print("🔄 Updated room: \(room.metadata.name)")
                saveRoomsToStorage()
            }
        } else {
            // Room doesn't exist yet - append it
            rooms.append(room)
            print("➕ Added new room: \(room.metadata.name)")
            saveRoomsToStorage()
        }
    }

    /// Smart update zones array - only update changed items to minimize UI flicker
    private func smartUpdateZones(with newZones: [HueZone]) {
        var updatedArray = zones

        for newZone in newZones {
            if let index = updatedArray.firstIndex(where: { $0.id == newZone.id }) {
                // Update existing zone only if data has changed
                if !areZonesEqual(updatedArray[index], newZone) {
                    updatedArray[index] = newZone
                }
            } else {
                // New zone - append it
                updatedArray.append(newZone)
            }
        }

        // Remove zones that no longer exist
        updatedArray.removeAll { existingZone in
            !newZones.contains { $0.id == existingZone.id }
        }

        zones = updatedArray
        saveZonesToStorage()
    }

    /// Update a single zone in the array without affecting other zones
    private func updateSingleZone(_ zone: HueZone) {
        if let index = zones.firstIndex(where: { $0.id == zone.id }) {
            // Update existing zone only if data has changed
            if !areZonesEqual(zones[index], zone) {
                zones[index] = zone
                print("🔄 Updated zone: \(zone.metadata.name)")
                saveZonesToStorage()
            }
        } else {
            // Zone doesn't exist yet - append it
            zones.append(zone)
            print("➕ Added new zone: \(zone.metadata.name)")
            saveZonesToStorage()
        }
    }

    /// Compare two rooms to check if they have changed
    private func areRoomsEqual(_ room1: HueRoom, _ room2: HueRoom) -> Bool {
        guard room1.id == room2.id else { return false }
        guard room1.metadata.name == room2.metadata.name else { return false }

        // Compare grouped lights
        let lights1 = room1.groupedLights ?? []
        let lights2 = room2.groupedLights ?? []

        guard lights1.count == lights2.count else { return false }

        for i in 0..<lights1.count {
            if !areGroupedLightsEqual(lights1[i], lights2[i]) {
                return false
            }
        }

        return true
    }

    /// Compare two zones to check if they have changed
    private func areZonesEqual(_ zone1: HueZone, _ zone2: HueZone) -> Bool {
        guard zone1.id == zone2.id else { return false }
        guard zone1.metadata.name == zone2.metadata.name else { return false }

        // Compare grouped lights
        let lights1 = zone1.groupedLights ?? []
        let lights2 = zone2.groupedLights ?? []

        guard lights1.count == lights2.count else { return false }

        for i in 0..<lights1.count {
            if !areGroupedLightsEqual(lights1[i], lights2[i]) {
                return false
            }
        }

        return true
    }

    /// Compare two grouped lights to check if they have changed
    private func areGroupedLightsEqual(_ light1: HueGroupedLight, _ light2: HueGroupedLight) -> Bool {
        guard light1.id == light2.id else { return false }
        guard light1.on?.on == light2.on?.on else { return false }
        guard light1.dimming?.brightness == light2.dimming?.brightness else { return false }
        guard light1.color_temperature?.mirek == light2.color_temperature?.mirek else { return false }
        guard light1.color?.xy?.x == light2.color?.xy?.x else { return false }
        guard light1.color?.xy?.y == light2.color?.xy?.y else { return false }

        return true
    }

    /// Manual refresh trigger - can be called from UI when control actions occur
    func triggerManualRefresh() async {
        print("🔄 Manual refresh triggered")
        await refreshAllData(forceRefresh: true)
    }

    // MARK: - Scene Management

    /// Fetch all scenes from the connected bridge
    public func fetchScenes() async {
        // Demo mode: Return cached/demo data
        if isDemoMode {
            print("🎭 fetchScenes: Demo mode - returning demo data")
            let demoScenes = getDemoScenes()
            self.scenes = demoScenes
            print("🎭 fetchScenes: Loaded \(demoScenes.count) demo scenes")
            return
        }

        guard currentConnectedBridge?.bridge != nil else {
            print("❌ fetchScenes: No connected bridge available")
            scenes = []
            return
        }

        print("🎬 fetchScenes: Requesting scenes from bridge")

        do {
            let response: HueScenesResponse = try await HueAPIService.shared.fetchScenes()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                print("❌ fetchScenes: Hue API v2 errors: \(errorMessages)")
                self.scenes = []
                return
            }

            // If no errors, update scenes
            self.scenes = response.data
            saveScenesToStorage()
            print("✅ fetchScenes: Success - retrieved \(response.data.count) scenes")
        } catch {
            print("❌ fetchScenes: Error: \(error.localizedDescription)")
            self.scenes = []
        }
    }

    /// Fetch scenes for a specific room
    public func fetchScenes(forRoomId roomId: String) async -> [HueScene] {
        // Ensure we have scenes loaded
        if scenes.isEmpty {
            await fetchScenes()
        }

        // Filter scenes by room ID
        let roomScenes = scenes.filter { $0.group.rid == roomId && $0.group.rtype == "room" }
        print("🎬 fetchScenes(forRoomId): Found \(roomScenes.count) scenes for room \(roomId)")
        return roomScenes
    }

    /// Fetch scenes for a specific zone
    public func fetchScenes(forZoneId zoneId: String) async -> [HueScene] {
        // Ensure we have scenes loaded
        if scenes.isEmpty {
            await fetchScenes()
        }

        // Filter scenes by zone ID
        let zoneScenes = scenes.filter { $0.group.rid == zoneId && $0.group.rtype == "zone" }
        print("🎬 fetchScenes(forZoneId): Found \(zoneScenes.count) scenes for zone \(zoneId)")
        return zoneScenes
    }

    /// Activate a specific scene
    /// Note: This does NOT automatically refresh. Use activateSceneWithConditionalRefresh()
    /// for SSE-aware refresh behavior.
    public func activateScene(_ sceneId: String) async -> Result<Void, Error> {
        // Demo mode: Just return success without network call
        if isDemoMode {
            print("🎭 activateScene: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge?.bridge != nil else {
            print("❌ activateScene: No connected bridge available")
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connection available"]))
        }

        do {
            try await HueAPIService.shared.activateScene(sceneId: sceneId)
            print("✅ activateScene: Successfully activated scene \(sceneId)")
            return .success(())
        } catch {
            print("❌ activateScene: Error: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Activate a scene and conditionally refresh if SSE is disconnected
    /// Only refreshes when SSE is not connected to avoid duplicate updates
    /// - Parameters:
    ///   - sceneId: The scene ID to activate
    ///   - roomId: Optional room ID to refresh after activation (if SSE disconnected)
    ///   - zoneId: Optional zone ID to refresh after activation (if SSE disconnected)
    public func activateSceneWithConditionalRefresh(
        _ sceneId: String,
        roomId: String? = nil,
        zoneId: String? = nil
    ) async -> Result<Void, Error> {
        // Activate the scene
        let result = await activateScene(sceneId)

        // Only refresh if SSE is NOT connected (prevents duplicate updates)
        guard case .success = result else {
            return result // Return error if activation failed
        }

        if !isSSEConnected {
            print("🔄 SSE disconnected - refreshing after scene activation")
            if let roomId = roomId {
                await refreshRoom(roomId: roomId)
            } else if let zoneId = zoneId {
                await refreshZone(zoneId: zoneId)
            }
        } else {
            print("✅ SSE connected - skipping refresh (will update via event stream)")
        }

        return result
    }

    /// Get the currently active scene for a specific room (if any)
    func getActiveScene(forRoomId roomId: String) async -> HueScene? {
        let roomScenes = await fetchScenes(forRoomId: roomId)
        let activeScene = roomScenes.first { $0.status?.active == "active" }

        if let scene = activeScene {
            print("🎬 getActiveScene(forRoomId): Found active scene '\(scene.metadata.name)' for room \(roomId)")
        } else {
            print("🎬 getActiveScene(forRoomId): No active scene for room \(roomId)")
        }

        return activeScene
    }

    /// Get the currently active scene for a specific zone (if any)
    func getActiveScene(forZoneId zoneId: String) async -> HueScene? {
        let zoneScenes = await fetchScenes(forZoneId: zoneId)
        let activeScene = zoneScenes.first { $0.status?.active == "active" }

        if let scene = activeScene {
            print("🎬 getActiveScene(forZoneId): Found active scene '\(scene.metadata.name)' for zone \(zoneId)")
        } else {
            print("🎬 getActiveScene(forZoneId): No active scene for zone \(zoneId)")
        }

        return activeScene
    }

    /// Extract colors from a scene's actions
    public func extractColorsFromScene(_ scene: HueScene) -> [Color] {
        guard let actions = scene.actions else {
            print("⚠️ extractColorsFromScene: Scene '\(scene.metadata.name)' has no actions")
            return []
        }

        let colors = actions.compactMap { action -> Color? in
            let brightness = action.action.dimming?.brightness ?? 100.0

            // Try XY color first
            if let xy = action.action.color?.xy {
                return xyToRGB(x: xy.x, y: xy.y, brightness: brightness)
            }

            // Try color temperature
            if let mirek = action.action.colorTemperature?.mirek {
                return mirekToRGB(mirek: mirek, brightness: brightness)
            }

            // No color data, return nil
            return nil
        }

        print("🎨 extractColorsFromScene: Extracted \(colors.count) colors from scene '\(scene.metadata.name)'")
        return colors
    }

    /// Extract average brightness from a scene's actions
    public func extractAverageBrightnessFromScene(_ scene: HueScene) -> Double? {
        guard let actions = scene.actions else {
            print("⚠️ extractAverageBrightnessFromScene: Scene '\(scene.metadata.name)' has no actions")
            return nil
        }

        let brightnesses = actions.compactMap { action -> Double? in
            return action.action.dimming?.brightness
        }

        guard !brightnesses.isEmpty else {
            print("⚠️ extractAverageBrightnessFromScene: No brightness data in scene '\(scene.metadata.name)'")
            return nil
        }

        let average = brightnesses.reduce(0.0, +) / Double(brightnesses.count)
        print("💡 extractAverageBrightnessFromScene: Average brightness for scene '\(scene.metadata.name)' is \(average)%")
        return average
    }

    // MARK: - Light Cache Management

    /// Fetch all lights in a single API call and cache them
    // MARK: - Local State Updates

    /// Update local room state optimistically after a successful control action
    /// This ensures the list view reflects changes immediately without waiting for a full refresh
    public func updateLocalRoomState(roomId: String, on: Bool? = nil, brightness: Double? = nil) {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else {
            print("⚠️ updateLocalRoomState: Room \(roomId) not found in local cache")
            return
        }

        var updatedRoom = rooms[index]

        // Update grouped lights by recreating the structs (they're immutable)
        if let groupedLights = updatedRoom.groupedLights, !groupedLights.isEmpty {
            let updatedGroupedLights = groupedLights.map { light in
                let newOn = on != nil ? HueGroupedLight.GroupedLightOn(on: on!) : light.on
                let newDimming = brightness != nil ? HueGroupedLight.GroupedLightDimming(brightness: brightness!) : light.dimming

                return HueGroupedLight(
                    id: light.id,
                    type: light.type,
                    on: newOn,
                    dimming: newDimming,
                    color_temperature: light.color_temperature,
                    color: light.color
                )
            }
            updatedRoom.groupedLights = updatedGroupedLights

            if let on = on {
                print("🔄 updateLocalRoomState: Updated room '\(updatedRoom.metadata.name)' on state to \(on)")
            }
            if let brightness = brightness {
                print("🔄 updateLocalRoomState: Updated room '\(updatedRoom.metadata.name)' brightness to \(Int(brightness))%")
            }
        }

        // Update the room in the array
        rooms[index] = updatedRoom

        // Save to cache
        saveRoomsToStorage()
    }

    /// Update local zone state optimistically after a successful control action
    /// This ensures the list view reflects changes immediately without waiting for a full refresh
    public func updateLocalZoneState(zoneId: String, on: Bool? = nil, brightness: Double? = nil) {
        guard let index = zones.firstIndex(where: { $0.id == zoneId }) else {
            print("⚠️ updateLocalZoneState: Zone \(zoneId) not found in local cache")
            return
        }

        var updatedZone = zones[index]

        // Update grouped lights by recreating the structs (they're immutable)
        if let groupedLights = updatedZone.groupedLights, !groupedLights.isEmpty {
            let updatedGroupedLights = groupedLights.map { light in
                let newOn = on != nil ? HueGroupedLight.GroupedLightOn(on: on!) : light.on
                let newDimming = brightness != nil ? HueGroupedLight.GroupedLightDimming(brightness: brightness!) : light.dimming

                return HueGroupedLight(
                    id: light.id,
                    type: light.type,
                    on: newOn,
                    dimming: newDimming,
                    color_temperature: light.color_temperature,
                    color: light.color
                )
            }
            updatedZone.groupedLights = updatedGroupedLights

            if let on = on {
                print("🔄 updateLocalZoneState: Updated zone '\(updatedZone.metadata.name)' on state to \(on)")
            }
            if let brightness = brightness {
                print("🔄 updateLocalZoneState: Updated zone '\(updatedZone.metadata.name)' brightness to \(Int(brightness))%")
            }
        }

        // Update the zone in the array
        zones[index] = updatedZone

        // Save to cache
        saveZonesToStorage()
    }

    /// Fetch the current state of a grouped light from the bridge
    /// Returns the updated grouped light data including current brightness
    public func fetchGroupedLight(groupedLightId: String) async -> HueGroupedLight? {
        guard let bridge = currentConnectedBridge?.bridge else { return nil }

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/grouped_light/\(groupedLightId)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(HueGroupedLightsResponse.self, from: data)
            return response.data.first
        } catch {
            print("❌ fetchGroupedLight: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Centralized Light Control Methods with Rate Limiting


    /// Set the power state of a grouped light (room or zone)
    /// - Parameters:
    ///   - id: The grouped light ID
    ///   - on: Power state (true = on, false = off)
    /// - Returns: Result with success or error
    public func setGroupedLightPower(id: String, on: Bool) async -> Result<Void, Error> {
        // Demo mode: Just return success without network call
        if isDemoMode {
            print("🎭 setGroupedLightPower: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connected"]))
        }

        do {
            try await HueAPIService.shared.setPower(groupedLightId: id, on: on)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Set the brightness of a grouped light (room or zone)
    /// - Parameters:
    ///   - id: The grouped light ID
    ///   - brightness: Brightness level (0.0 to 100.0)
    /// - Returns: Result with success or error
    public func setGroupedLightBrightness(id: String, brightness: Double) async -> Result<Void, Error> {
        // Demo mode: Just return success without network call
        if isDemoMode {
            print("🎭 setGroupedLightBrightness: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connected"]))
        }

        do {
            try await HueAPIService.shared.setBrightness(groupedLightId: id, brightness: brightness)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Set both power state and brightness of a grouped light in a single command
    /// Note: This now makes two separate calls (power then brightness) through HueAPIService
    /// - Parameters:
    ///   - id: The grouped light ID
    ///   - on: Power state (true = on, false = off)
    ///   - brightness: Brightness level (0.0 to 100.0)
    /// - Returns: Result with success or error
    public func setGroupedLightPowerAndBrightness(id: String, on: Bool, brightness: Double) async -> Result<Void, Error> {
        // Demo mode: Just return success without network call
        if isDemoMode {
            print("🎭 setGroupedLightPowerAndBrightness: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connected"]))
        }

        do {
            // Make two separate calls - rate limiting is handled by HueAPIService
            try await HueAPIService.shared.setPower(groupedLightId: id, on: on)
            try await HueAPIService.shared.setBrightness(groupedLightId: id, brightness: brightness)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Bulk Operations

    /// Turn off all lights in all rooms and zones
    ///
    /// Uses grouped_light endpoints to turn off lights by room/zone
    ///
    /// API Endpoint: PUT /clip/v2/resource/grouped_light/{id}
    /// Rate Limit: 1 command per second (automatically enforced by sendGroupedLightCommand)
    ///
    /// Request Payload:
    /// ```json
    /// {"on": {"on": false}}
    /// ```
    public func turnOffAllLights() async -> Result<Void, Error> {
        // Demo mode: Update local state only
        if isDemoMode {
            print("🎭 turnOffAllLights: Demo mode - updating local state only")

            // Update grouped lights in rooms to reflect off state
            for index in rooms.indices {
                if var groupedLights = rooms[index].groupedLights {
                    for i in groupedLights.indices {
                        groupedLights[i] = HueGroupedLight(
                            id: groupedLights[i].id,
                            type: groupedLights[i].type,
                            on: HueGroupedLight.GroupedLightOn(on: false),
                            dimming: groupedLights[i].dimming,
                            color_temperature: groupedLights[i].color_temperature,
                            color: groupedLights[i].color
                        )
                    }
                    rooms[index].groupedLights = groupedLights
                }
            }

            // Update grouped lights in zones to reflect off state
            for index in zones.indices {
                if var groupedLights = zones[index].groupedLights {
                    for i in groupedLights.indices {
                        groupedLights[i] = HueGroupedLight(
                            id: groupedLights[i].id,
                            type: groupedLights[i].type,
                            on: HueGroupedLight.GroupedLightOn(on: false),
                            dimming: groupedLights[i].dimming,
                            color_temperature: groupedLights[i].color_temperature,
                            color: groupedLights[i].color
                        )
                    }
                    zones[index].groupedLights = groupedLights
                }
            }

            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connected"]))
        }

        print("🔴 Turning off all lights...")

        // Collect all grouped light IDs from rooms and zones
        var groupedLightIds: [String] = []
        for room in rooms {
            if let groupedLights = room.groupedLights {
                groupedLightIds.append(contentsOf: groupedLights.map { $0.id })
            }
        }
        for zone in zones {
            if let groupedLights = zone.groupedLights {
                groupedLightIds.append(contentsOf: groupedLights.map { $0.id })
            }
        }

        guard !groupedLightIds.isEmpty else {
            print("⚠️ No grouped lights found to turn off")
            return .success(())
        }

        print("💡 Found \(groupedLightIds.count) grouped lights to turn off")
        print("⏱️ Estimated time: ~\(groupedLightIds.count) seconds (1 group/sec)")

        // Turn off each grouped light using HueAPIService (rate limiting automatically enforced)
        var successCount = 0
        var failureCount = 0

        for groupedLightId in groupedLightIds {
            do {
                try await HueAPIService.shared.setPower(groupedLightId: groupedLightId, on: false)
                successCount += 1
                print("  ✓ Turned off grouped light \(groupedLightId.prefix(8))... (\(successCount)/\(groupedLightIds.count))")
            } catch {
                failureCount += 1
                print("  ✗ Failed to turn off grouped light \(groupedLightId.prefix(8))...: \(error.localizedDescription)")
            }
        }

        // Update grouped lights in rooms and zones to reflect off state
        for index in rooms.indices {
            if var groupedLights = rooms[index].groupedLights {
                for i in groupedLights.indices {
                    groupedLights[i] = HueGroupedLight(
                        id: groupedLights[i].id,
                        type: groupedLights[i].type,
                        on: HueGroupedLight.GroupedLightOn(on: false),
                        dimming: groupedLights[i].dimming,
                        color_temperature: groupedLights[i].color_temperature,
                        color: groupedLights[i].color
                    )
                }
                rooms[index].groupedLights = groupedLights
            }
        }

        for index in zones.indices {
            if var groupedLights = zones[index].groupedLights {
                for i in groupedLights.indices {
                    groupedLights[i] = HueGroupedLight(
                        id: groupedLights[i].id,
                        type: groupedLights[i].type,
                        on: HueGroupedLight.GroupedLightOn(on: false),
                        dimming: groupedLights[i].dimming,
                        color_temperature: groupedLights[i].color_temperature,
                        color: groupedLights[i].color
                    )
                }
                zones[index].groupedLights = groupedLights
            }
        }

        saveRoomsToStorage()
        saveZonesToStorage()

        print("✅ All lights turned off: \(successCount) succeeded, \(failureCount) failed")
        return .success(())
    }

}
