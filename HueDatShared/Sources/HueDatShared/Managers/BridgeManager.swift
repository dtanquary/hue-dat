//
//  BridgeManager.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import Combine
import Security
import os

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

    // Scene pinning - delegated to ScenePinningManager
    public let scenePinning = ScenePinningManager()

    /// Published proxy so existing views that observe `pinnedSceneIds` continue to work.
    @Published public private(set) var pinnedSceneIds: [String: [String: [String]]] = [:]

    // Event broadcasting for connection validation
    private let connectionValidationSubject = PassthroughSubject<ConnectionValidationResult, Never>()
    public var connectionValidationPublisher: AnyPublisher<ConnectionValidationResult, Never> {
        connectionValidationSubject.eraseToAnyPublisher()
    }

    // SSE event processing - delegated to SSEEventProcessor
    public private(set) lazy var sseProcessor: SSEEventProcessor = SSEEventProcessor(bridgeManager: self)
    @Published public var isSSEConnected: Bool = false
    public var reconnectAttempts = 0  // Public so ContentView can reset on successful connection

    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    private let cachedRoomsKey = "CachedRooms"
    private let cachedZonesKey = "CachedZones"
    private let cachedScenesKey = "CachedScenes"
    private let demoModeKey = "DemoMode"

    /// Combine subscription to forward ScenePinningManager changes to local proxy.
    private var pinningSubscription: AnyCancellable?

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
            AppLogger.bridge.debug("Cleaned up old lights cache")
        }
        loadRoomsFromStorage()
        loadZonesFromStorage()
        loadScenesFromStorage()

        // Sync pinning state from ScenePinningManager
        pinnedSceneIds = scenePinning.pinnedSceneIds
        pinningSubscription = scenePinning.$pinnedSceneIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.pinnedSceneIds = newValue
            }
    }
    
    public func saveConnection(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        // Validate bridge IP is not localhost (prevent data corruption)
        if bridge.internalipaddress == "127.0.0.1" ||
           bridge.internalipaddress == "localhost" ||
           bridge.internalipaddress == "::1" {
            AppLogger.bridge.error("Refusing to save bridge with localhost IP: \(bridge.internalipaddress, privacy: .private)")
            AppLogger.bridge.error("Bridge must be on local network (e.g., 192.168.x.x or 10.0.x.x)")
            return
        }

        let connectionInfo = BridgeConnectionInfo(bridge: bridge, registrationResponse: registrationResponse)

        // Save credentials to Keychain
        let bridgeId = bridge.id
        saveToKeychain(key: "\(bridgeId)_username", value: registrationResponse.username)
        if let clientkey = registrationResponse.clientkey {
            saveToKeychain(key: "\(bridgeId)_clientkey", value: clientkey)
        }

        // Save non-sensitive bridge info to UserDefaults (without credentials)
        do {
            let data = try JSONEncoder().encode(connectionInfo)
            userDefaults.set(data, forKey: connectedBridgeKey)

            connectedBridge = connectionInfo
            AppLogger.bridge.info("Bridge connection saved successfully")
            AppLogger.bridge.debug("Bridge: \(bridge.displayName, privacy: .public) (\(bridge.shortId, privacy: .private))")
            AppLogger.bridge.debug("IP Address: \(bridge.internalipaddress, privacy: .private)")
            #if DEBUG
            AppLogger.bridge.debug("Username: \(registrationResponse.username, privacy: .private)")
            AppLogger.bridge.debug("ClientKey: \(registrationResponse.clientkey ?? "nil", privacy: .private)")
            #endif
            AppLogger.bridge.debug("Connected Date: \(connectionInfo.connectedDate.description, privacy: .public)")
            AppLogger.bridge.debug("Data size: \(data.count, privacy: .public) bytes")

            // Verify the save by immediately reading it back
            if let verifyData = userDefaults.data(forKey: connectedBridgeKey) {
                AppLogger.bridge.info("Verification: Data successfully retrieved from UserDefaults (\(verifyData.count, privacy: .public) bytes)")
            } else {
                AppLogger.bridge.error("Verification failed: Could not retrieve data from UserDefaults")
            }
        } catch {
            AppLogger.bridge.error("Failed to save bridge connection: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    public func disconnectBridge() {
        // Remove bridge-specific pinned scenes and Keychain credentials before clearing connection
        if let bridgeId = connectedBridge?.bridge.id {
            scenePinning.clearPinnedScenes(forBridgeId: bridgeId)
            deleteFromKeychain(key: "\(bridgeId)_username")
            deleteFromKeychain(key: "\(bridgeId)_clientkey")
        }

        userDefaults.removeObject(forKey: connectedBridgeKey)
        userDefaults.removeObject(forKey: cachedRoomsKey)
        userDefaults.removeObject(forKey: cachedZonesKey)
        userDefaults.removeObject(forKey: cachedScenesKey)
        connectedBridge = nil
        isConnectionValidated = false
        rooms = []
        zones = []
        scenes = []
        sseProcessor.rebuildGroupedLightToRoomMap()
        sseProcessor.rebuildGroupedLightToZoneMap()
        AppLogger.bridge.info("Bridge disconnected and cleared from storage")
    }

    // MARK: - Demo Mode Management

    /// Load demo mode state from UserDefaults
    private func loadDemoModeState() {
        isDemoMode = userDefaults.bool(forKey: demoModeKey)
        if isDemoMode {
            AppLogger.bridge.debug("Demo mode is ENABLED")
        }
    }

    /// Enable demo mode for offline demonstration
    public func enableDemoMode() {
        isDemoMode = true
        userDefaults.set(true, forKey: demoModeKey)
        AppLogger.bridge.debug("Demo mode ENABLED")
    }

    /// Disable demo mode and return to normal operation
    public func disableDemoMode() {
        isDemoMode = false
        userDefaults.set(false, forKey: demoModeKey)
        AppLogger.bridge.debug("Demo mode DISABLED")
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
            colorTemperature: nil,
            color: HueGroupedLight.GroupedLightColor(
                xy: HueGroupedLight.GroupedLightColor.GroupedLightColorXY(x: 0.4573, y: 0.41),
                gamut: nil,
                gamutType: nil
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
                    colorTemperature: HueGroupedLight.GroupedLightColorTemperature(mirek: 366, mirekValid: true, mirekSchema: nil),
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
                    colorTemperature: HueGroupedLight.GroupedLightColorTemperature(mirek: 250, mirekValid: true, mirekSchema: nil),
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
                    colorTemperature: nil,
                    color: nil
                )]
            )
        ]
    }

    // MARK: - SSE Event Processing (delegated to SSEEventProcessor)

    /// Start listening to SSE events from HueAPIService
    public func startListeningToSSEEvents() {
        sseProcessor.startListeningToSSEEvents()
    }

    /// Stop listening to SSE events
    public func stopListeningToSSEEvents() {
        sseProcessor.stopListeningToSSEEvents()
    }

    /// Manually reconnect SSE stream (for user-initiated reconnection)
    public func reconnectSSE() async {
        await sseProcessor.reconnectSSE()
    }

    private func loadConnectedBridge() {
        AppLogger.bridge.debug("Loading bridge connection from UserDefaults...")

        guard let data = userDefaults.data(forKey: connectedBridgeKey) else {
            AppLogger.bridge.error("No saved bridge connection found")
            return
        }

        AppLogger.bridge.debug("Found saved data: \(data.count, privacy: .public) bytes")

        do {
            var connection = try JSONDecoder().decode(BridgeConnectionInfo.self, from: data)

            // Try Keychain first for credentials, fall back to UserDefaults (migration)
            let bridgeId = connection.bridge.id
            if let keychainUsername = loadFromKeychain(key: "\(bridgeId)_username") {
                // Credentials found in Keychain - use them
                let keychainClientkey = loadFromKeychain(key: "\(bridgeId)_clientkey")
                connection = BridgeConnectionInfo(
                    bridge: connection.bridge,
                    username: keychainUsername,
                    clientkey: keychainClientkey,
                    connectedDate: connection.connectedDate
                )
                AppLogger.bridge.debug("Loaded credentials from Keychain")
            } else if !connection.username.isEmpty {
                // Migrate credentials from UserDefaults to Keychain
                saveToKeychain(key: "\(bridgeId)_username", value: connection.username)
                if let clientkey = connection.clientkey {
                    saveToKeychain(key: "\(bridgeId)_clientkey", value: clientkey)
                }
                AppLogger.bridge.debug("Migrated credentials from UserDefaults to Keychain")
            }

            connectedBridge = connection
            AppLogger.bridge.info("Loaded saved bridge connection")
            AppLogger.bridge.debug("Bridge: \(connection.bridge.shortId, privacy: .private)")
            AppLogger.bridge.debug("Address: \(connection.bridge.displayAddress, privacy: .private)")
            AppLogger.bridge.debug("Internal IP: \(connection.bridge.internalipaddress, privacy: .private)")
            #if DEBUG
            AppLogger.bridge.debug("Username: \(connection.username, privacy: .private)")
            AppLogger.bridge.debug("ClientKey: \(connection.clientkey ?? "nil", privacy: .private)")
            #endif
            AppLogger.bridge.debug("Connected Date: \(connection.connectedDate.description, privacy: .public)")

            // Validate that the bridge IP is not localhost (corrupted data)
            if connection.bridge.internalipaddress == "127.0.0.1" ||
               connection.bridge.internalipaddress == "localhost" ||
               connection.bridge.internalipaddress == "::1" {
                AppLogger.bridge.error("Invalid bridge IP detected (localhost) - clearing corrupted connection")
                userDefaults.removeObject(forKey: connectedBridgeKey)
                connectedBridge = nil
                isConnectionValidated = false
                AppLogger.bridge.debug("Cleared localhost connection - please re-discover your bridge")
            }
        } catch {
            AppLogger.bridge.error("Failed to load bridge connection: \(error.localizedDescription, privacy: .public)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: connectedBridgeKey)
            isConnectionValidated = false
            AppLogger.bridge.debug("Cleaned up corrupted data")
        }
    }

    // MARK: - Rooms and Zones Persistence

    private func loadRoomsFromStorage() {
        guard let data = userDefaults.data(forKey: cachedRoomsKey) else {
            AppLogger.bridge.debug("No cached rooms found")
            return
        }

        do {
            rooms = try JSONDecoder().decode([HueRoom].self, from: data)
            sseProcessor.rebuildGroupedLightToRoomMap()
            AppLogger.bridge.info("Loaded \(self.rooms.count, privacy: .public) cached rooms from storage")
        } catch {
            AppLogger.bridge.error("Failed to load cached rooms: \(error.localizedDescription, privacy: .public)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedRoomsKey)
        }
    }

    private func saveRoomsToStorage() {
        do {
            let data = try JSONEncoder().encode(rooms)
            userDefaults.set(data, forKey: cachedRoomsKey)
            AppLogger.bridge.debug("Saved \(self.rooms.count, privacy: .public) rooms to storage (\(data.count, privacy: .public) bytes)")
        } catch {
            AppLogger.bridge.error("Failed to save rooms to storage: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadZonesFromStorage() {
        guard let data = userDefaults.data(forKey: cachedZonesKey) else {
            AppLogger.bridge.debug("No cached zones found")
            return
        }

        do {
            zones = try JSONDecoder().decode([HueZone].self, from: data)
            sseProcessor.rebuildGroupedLightToZoneMap()
            AppLogger.bridge.info("Loaded \(self.zones.count, privacy: .public) cached zones from storage")
        } catch {
            AppLogger.bridge.error("Failed to load cached zones: \(error.localizedDescription, privacy: .public)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedZonesKey)
        }
    }

    private func saveZonesToStorage() {
        do {
            let data = try JSONEncoder().encode(zones)
            userDefaults.set(data, forKey: cachedZonesKey)
            AppLogger.bridge.debug("Saved \(self.zones.count, privacy: .public) zones to storage (\(data.count, privacy: .public) bytes)")
        } catch {
            AppLogger.bridge.error("Failed to save zones to storage: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadScenesFromStorage() {
        guard let data = userDefaults.data(forKey: cachedScenesKey) else {
            AppLogger.bridge.debug("No cached scenes found")
            return
        }

        do {
            scenes = try JSONDecoder().decode([HueScene].self, from: data)
            AppLogger.bridge.info("Loaded \(self.scenes.count, privacy: .public) cached scenes from storage")
        } catch {
            AppLogger.bridge.error("Failed to load cached scenes: \(error.localizedDescription, privacy: .public)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedScenesKey)
        }
    }

    private func saveScenesToStorage() {
        do {
            let data = try JSONEncoder().encode(scenes)
            userDefaults.set(data, forKey: cachedScenesKey)
            AppLogger.bridge.debug("Saved \(self.scenes.count, privacy: .public) scenes to storage (\(data.count, privacy: .public) bytes)")
        } catch {
            AppLogger.bridge.error("Failed to save scenes to storage: \(error.localizedDescription, privacy: .public)")
        }
    }

    public var isConnected: Bool {
        connectedBridge != nil
    }

    /// Validate that the current connection is alive/reachable.
    /// Broadcasts the result via connectionValidationPublisher.
    public func validateConnection() async {
        // Demo mode: Skip validation and return success
        if isDemoMode {
            AppLogger.bridge.debug("validateConnection: Demo mode - skipping validation")
            isConnectionValidated = true
            connectionValidationSubject.send(.success)
            return
        }

        guard let bridge = currentConnectedBridge?.bridge else {
            AppLogger.bridge.error("validateConnection: No connected bridge available")
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
            AppLogger.bridge.info("validateConnection: Success")
            self.isConnectionValidated = true
            connectionValidationSubject.send(.success)
        } catch {
            AppLogger.bridge.error("validateConnection: Error: \(error.localizedDescription, privacy: .public)")
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
            AppLogger.bridge.debug("getRooms: Demo mode - returning demo data")
            let demoRooms = getDemoRooms()
            self.rooms = demoRooms
            sseProcessor.rebuildGroupedLightToRoomMap()
            AppLogger.bridge.debug("getRooms: Loaded \(demoRooms.count, privacy: .public) demo rooms")
            return
        }

        // PROTECTION 1: Concurrent call protection
        guard !isRefreshingRooms else {
            AppLogger.bridge.debug("getRooms: Already refreshing rooms, skipping duplicate call")
            return
        }

        // PROTECTION 2: Debouncing - skip if refreshed recently (unless forced)
        if !forceRefresh {
            if let lastRefresh = lastRoomsRefreshTime,
               Date().timeIntervalSince(lastRefresh) < refreshDebounceInterval {
                let timeRemaining = refreshDebounceInterval - Date().timeIntervalSince(lastRefresh)
                AppLogger.bridge.debug("getRooms: Debounced - last refresh was \(Int(Date().timeIntervalSince(lastRefresh)), privacy: .public)s ago, waiting \(Int(timeRemaining), privacy: .public)s")
                return
            }
        } else {
            AppLogger.bridge.debug("getRooms: Force refresh - bypassing debounce")
        }

        // Set loading state immediately
        isLoadingRooms = true
        isRefreshing = true

        guard let bridge = currentConnectedBridge?.bridge else {
            AppLogger.bridge.error("getRooms: No connected bridge available")
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

        AppLogger.bridge.debug("getRooms: Requesting rooms from bridge")

        do {
            // Fetch basic rooms list (without enrichment)
            let response = try await HueAPIService.shared.fetchRooms()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                AppLogger.bridge.error("getRooms: Hue API v2 errors: \(errorMessages, privacy: .public)")
                // PROTECTION 3: Keep existing data, set error instead
                refreshError = "API Error: \(errorMessages)"
                isLoadingRooms = false
                isRefreshingRooms = false
                updateCombinedRefreshState()  // Update combined state
                return
            }

            AppLogger.bridge.info("getRooms: Success - retrieved \(response.data.count, privacy: .public) rooms")

            // Enrich rooms with grouped light status
            var enrichedRooms = response.data
            for (index, room) in enrichedRooms.enumerated() {
                if let services = room.services,
                   let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                    if let groupedLight = await fetchGroupedLight(groupedLightId: groupedLightService.rid) {
                        enrichedRooms[index].groupedLights = [groupedLight]
                        AppLogger.bridge.debug("Enriched room '\(room.metadata.name, privacy: .public)' with grouped light status (brightness: \(groupedLight.dimming?.brightness ?? 0, privacy: .public)%)")
                    }
                }
            }

            self.rooms = enrichedRooms
            sseProcessor.rebuildGroupedLightToRoomMap()
            saveRoomsToStorage()  // Cache successful refresh
            refreshError = nil  // Clear any previous errors
            AppLogger.bridge.debug("getRooms: Completed with \(enrichedRooms.count, privacy: .public) rooms")

        } catch {
            AppLogger.bridge.error("getRooms: Error: \(error.localizedDescription, privacy: .public)")
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
            AppLogger.bridge.debug("getZones: Demo mode - returning demo data")
            let demoZones = getDemoZones()
            self.zones = demoZones
            sseProcessor.rebuildGroupedLightToZoneMap()
            AppLogger.bridge.debug("getZones: Loaded \(demoZones.count, privacy: .public) demo zones")
            return
        }

        // PROTECTION 1: Concurrent call protection
        guard !isRefreshingZones else {
            AppLogger.bridge.debug("getZones: Already refreshing zones, skipping duplicate call")
            return
        }

        // PROTECTION 2: Debouncing - skip if refreshed recently (unless forced)
        if !forceRefresh {
            if let lastRefresh = lastZonesRefreshTime,
               Date().timeIntervalSince(lastRefresh) < refreshDebounceInterval {
                let timeRemaining = refreshDebounceInterval - Date().timeIntervalSince(lastRefresh)
                AppLogger.bridge.debug("getZones: Debounced - last refresh was \(Int(Date().timeIntervalSince(lastRefresh)), privacy: .public)s ago, waiting \(Int(timeRemaining), privacy: .public)s")
                return
            }
        } else {
            AppLogger.bridge.debug("getZones: Force refresh - bypassing debounce")
        }

        // Set loading state immediately
        isLoadingZones = true
        isRefreshing = true

        guard let bridge = currentConnectedBridge?.bridge else {
            AppLogger.bridge.error("getZones: No connected bridge available")
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

        AppLogger.bridge.debug("getZones: Requesting zones from bridge")

        do {
            // Fetch basic zones list (without enrichment)
            let response = try await HueAPIService.shared.fetchZones()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                AppLogger.bridge.error("getZones: Hue API v2 errors: \(errorMessages, privacy: .public)")
                // PROTECTION 3: Keep existing data, set error instead
                refreshError = "API Error: \(errorMessages)"
                isLoadingZones = false
                isRefreshingZones = false
                updateCombinedRefreshState()  // Update combined state
                return
            }

            AppLogger.bridge.info("getZones: Success - retrieved \(response.data.count, privacy: .public) zones")

            // Enrich zones with grouped light status
            var enrichedZones = response.data
            for (index, zone) in enrichedZones.enumerated() {
                if let services = zone.services,
                   let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                    if let groupedLight = await fetchGroupedLight(groupedLightId: groupedLightService.rid) {
                        enrichedZones[index].groupedLights = [groupedLight]
                        AppLogger.bridge.debug("Enriched zone '\(zone.metadata.name, privacy: .public)' with grouped light status (brightness: \(groupedLight.dimming?.brightness ?? 0, privacy: .public)%)")
                    }
                }
            }

            self.zones = enrichedZones
            sseProcessor.rebuildGroupedLightToZoneMap()
            saveZonesToStorage()  // Cache successful refresh
            refreshError = nil  // Clear any previous errors
            AppLogger.bridge.debug("getZones: Completed with \(enrichedZones.count, privacy: .public) zones")

        } catch {
            AppLogger.bridge.error("getZones: Error: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Color Conversion (delegated to ColorConverter)

    /// Convert CIE XY color space to RGB (backward-compatible wrapper)
    func xyToRGB(x: Double, y: Double, brightness: Double) -> Color {
        ColorConverter.xyToRGB(x: x, y: y, brightness: brightness)
    }

    /// Convert color temperature (mirek) to RGB (backward-compatible wrapper)
    func mirekToRGB(mirek: Int, brightness: Double) -> Color {
        ColorConverter.mirekToRGB(mirek: mirek, brightness: brightness)
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
        AppLogger.bridge.debug("Refreshing all data (rooms, zones, scenes) \(forceRefresh ? "[FORCED]" : "", privacy: .public)")

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
        AppLogger.bridge.info("Refresh completed at \(self.lastRefreshTimestamp!.description, privacy: .public)")

        // Check SSE connection status and attempt reconnection if needed
        if !isSSEConnected && isConnected {
            AppLogger.sse.debug("SSE not connected after refresh - attempting reconnection")
            startListeningToSSEEvents()

            // Trigger the actual stream start
            Task {
                do {
                    try await HueAPIService.shared.startEventStream()
                    AppLogger.sse.info("SSE stream restarted successfully")
                } catch {
                    AppLogger.sse.error("Failed to restart SSE stream: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Start periodic background refresh (every 60 seconds)
    public func startPeriodicRefresh() {
        // Check if timer is already running - prevent duplicate timers
        if refreshTimer != nil {
            AppLogger.bridge.debug("Periodic refresh already running, skipping duplicate start")
            return
        }

        AppLogger.bridge.debug("Starting periodic refresh (60 second interval)")

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
        AppLogger.bridge.debug("Stopped periodic refresh")
    }

    // MARK: - Generic Smart Update Helpers

    /// Smart update a collection of GroupedLightContainers - only update changed items to minimize UI flicker
    private func smartUpdate<T: GroupedLightContainer>(_ existing: inout [T], with new: [T]) {
        for newItem in new {
            if let index = existing.firstIndex(where: { $0.id == newItem.id }) {
                // Update existing item only if data has changed (uses custom == on the type)
                if existing[index] != newItem {
                    existing[index] = newItem
                }
            } else {
                // New item - append it
                existing.append(newItem)
            }
        }

        // Remove items that no longer exist
        existing.removeAll { item in
            !new.contains { $0.id == item.id }
        }
    }

    /// Update a single GroupedLightContainer in a collection without affecting other items
    private func updateSingle<T: GroupedLightContainer>(_ item: T, in collection: inout [T], save: () -> Void) {
        if let index = collection.firstIndex(where: { $0.id == item.id }) {
            // Update existing item only if data has changed
            if collection[index] != item {
                collection[index] = item
                AppLogger.bridge.debug("Updated \(T.apiGroupType, privacy: .public): \(item.displayName, privacy: .public)")
                save()
            }
        } else {
            // Item doesn't exist yet - append it
            collection.append(item)
            AppLogger.bridge.debug("Added new \(T.apiGroupType, privacy: .public): \(item.displayName, privacy: .public)")
            save()
        }
    }

    /// Smart update rooms array - only update changed items to minimize UI flicker
    private func smartUpdateRooms(with newRooms: [HueRoom]) {
        smartUpdate(&rooms, with: newRooms)
        sseProcessor.rebuildGroupedLightToRoomMap()
        saveRoomsToStorage()
    }

    /// Update a single room in the array without affecting other rooms
    private func updateSingleRoom(_ room: HueRoom) {
        updateSingle(room, in: &rooms, save: saveRoomsToStorage)
    }

    /// Smart update zones array - only update changed items to minimize UI flicker
    private func smartUpdateZones(with newZones: [HueZone]) {
        smartUpdate(&zones, with: newZones)
        sseProcessor.rebuildGroupedLightToZoneMap()
        saveZonesToStorage()
    }

    /// Update a single zone in the array without affecting other zones
    private func updateSingleZone(_ zone: HueZone) {
        updateSingle(zone, in: &zones, save: saveZonesToStorage)
    }

    /// Manual refresh trigger - can be called from UI when control actions occur
    func triggerManualRefresh() async {
        AppLogger.bridge.debug("Manual refresh triggered")
        await refreshAllData(forceRefresh: true)
    }

    // MARK: - Scene Management

    /// Fetch all scenes from the connected bridge
    public func fetchScenes() async {
        // Demo mode: Return cached/demo data
        if isDemoMode {
            AppLogger.bridge.debug("fetchScenes: Demo mode - returning demo data")
            let demoScenes = getDemoScenes()
            self.scenes = demoScenes
            AppLogger.bridge.debug("fetchScenes: Loaded \(demoScenes.count, privacy: .public) demo scenes")
            return
        }

        guard currentConnectedBridge?.bridge != nil else {
            AppLogger.bridge.error("fetchScenes: No connected bridge available")
            return
        }

        AppLogger.bridge.debug("fetchScenes: Requesting scenes from bridge")

        do {
            let response: HueScenesResponse = try await HueAPIService.shared.fetchScenes()

            // Check for errors first
            if !response.errors.isEmpty {
                let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                AppLogger.bridge.error("fetchScenes: Hue API v2 errors: \(errorMessages, privacy: .public)")
                // Keep existing scenes data on error
                refreshError = "API Error: \(errorMessages)"
                return
            }

            // If no errors, update scenes
            self.scenes = response.data
            saveScenesToStorage()
            scenePinning.validateAndCleanPinnedScenes(bridgeId: connectedBridge?.bridge.id, scenes: scenes)
            refreshError = nil
            AppLogger.bridge.info("fetchScenes: Success - retrieved \(response.data.count, privacy: .public) scenes")
        } catch {
            AppLogger.bridge.error("fetchScenes: Error: \(error.localizedDescription, privacy: .public)")
            // Keep existing scenes data on error
            refreshError = "Error: \(error.localizedDescription)"
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
        AppLogger.bridge.debug("fetchScenes(forRoomId): Found \(roomScenes.count, privacy: .public) scenes for room \(roomId, privacy: .public)")
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
        AppLogger.bridge.debug("fetchScenes(forZoneId): Found \(zoneScenes.count, privacy: .public) scenes for zone \(zoneId, privacy: .public)")
        return zoneScenes
    }

    /// Activate a specific scene
    /// Note: This does NOT automatically refresh. Use activateSceneWithConditionalRefresh()
    /// for SSE-aware refresh behavior.
    public func activateScene(_ sceneId: String) async -> Result<Void, Error> {
        // Demo mode: Just return success without network call
        if isDemoMode {
            AppLogger.bridge.debug("activateScene: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge?.bridge != nil else {
            AppLogger.bridge.error("activateScene: No connected bridge available")
            return .failure(BridgeManagerError.noBridgeAvailable)
        }

        do {
            try await HueAPIService.shared.activateScene(sceneId: sceneId)
            AppLogger.bridge.info("activateScene: Successfully activated scene \(sceneId, privacy: .public)")
            return .success(())
        } catch {
            AppLogger.bridge.error("activateScene: Error: \(error.localizedDescription, privacy: .public)")
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
            AppLogger.bridge.debug("SSE disconnected - refreshing after scene activation")
            if let roomId = roomId {
                await refreshRoom(roomId: roomId)
            } else if let zoneId = zoneId {
                await refreshZone(zoneId: zoneId)
            }
        } else {
            AppLogger.bridge.info("SSE connected - skipping refresh (will update via event stream)")
        }

        return result
    }

    /// Get the currently active scene for a specific room (if any)
    func getActiveScene(forRoomId roomId: String) async -> HueScene? {
        let roomScenes = await fetchScenes(forRoomId: roomId)
        let activeScene = roomScenes.first { $0.status?.active == "active" }

        if let scene = activeScene {
            AppLogger.bridge.debug("getActiveScene(forRoomId): Found active scene '\(scene.metadata.name, privacy: .public)' for room \(roomId, privacy: .public)")
        } else {
            AppLogger.bridge.debug("getActiveScene(forRoomId): No active scene for room \(roomId, privacy: .public)")
        }

        return activeScene
    }

    /// Get the currently active scene for a specific zone (if any)
    func getActiveScene(forZoneId zoneId: String) async -> HueScene? {
        let zoneScenes = await fetchScenes(forZoneId: zoneId)
        let activeScene = zoneScenes.first { $0.status?.active == "active" }

        if let scene = activeScene {
            AppLogger.bridge.debug("getActiveScene(forZoneId): Found active scene '\(scene.metadata.name, privacy: .public)' for zone \(zoneId, privacy: .public)")
        } else {
            AppLogger.bridge.debug("getActiveScene(forZoneId): No active scene for zone \(zoneId, privacy: .public)")
        }

        return activeScene
    }

    /// Extract colors from a scene's actions
    public func extractColorsFromScene(_ scene: HueScene) -> [Color] {
        guard let actions = scene.actions else {
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

            // No color data (likely a dynamic scene like gradients)
            return nil
        }

        return colors
    }

    /// Extract average brightness from a scene's actions
    public func extractAverageBrightnessFromScene(_ scene: HueScene) -> Double? {
        guard let actions = scene.actions else {
            AppLogger.bridge.warning("extractAverageBrightnessFromScene: Scene '\(scene.metadata.name, privacy: .public)' has no actions")
            return nil
        }

        let brightnesses = actions.compactMap { action -> Double? in
            return action.action.dimming?.brightness
        }

        guard !brightnesses.isEmpty else {
            AppLogger.bridge.warning("extractAverageBrightnessFromScene: No brightness data in scene '\(scene.metadata.name, privacy: .public)'")
            return nil
        }

        let average = brightnesses.reduce(0.0, +) / Double(brightnesses.count)
        AppLogger.bridge.debug("extractAverageBrightnessFromScene: Average brightness for scene '\(scene.metadata.name, privacy: .public)' is \(average, privacy: .public)%")
        return average
    }

    // MARK: - Scene Pinning (delegated to ScenePinningManager)

    /// Pin a scene to a specific room or zone
    public func pinScene(sceneId: String, forGroupId groupId: String) {
        scenePinning.pinScene(sceneId: sceneId, forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Unpin a scene from a specific room or zone
    public func unpinScene(sceneId: String, forGroupId groupId: String) {
        scenePinning.unpinScene(sceneId: sceneId, forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Toggle pin state for a scene
    public func toggleScenePin(sceneId: String, forGroupId groupId: String) {
        scenePinning.toggleScenePin(sceneId: sceneId, forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Check if a scene is pinned
    public func isScenePinned(sceneId: String, forGroupId groupId: String) -> Bool {
        scenePinning.isScenePinned(sceneId: sceneId, forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Get all pinned scenes for a specific group (room or zone)
    public func getPinnedScenes(forGroupId groupId: String) -> [HueScene] {
        scenePinning.getPinnedScenes(forGroupId: groupId, bridgeId: connectedBridge?.bridge.id, scenes: scenes)
    }

    /// Get all pinned scenes for a specific room
    public func getPinnedScenes(forRoomId roomId: String) -> [HueScene] {
        getPinnedScenes(forGroupId: roomId)
    }

    /// Get all pinned scenes for a specific zone
    public func getPinnedScenes(forZoneId zoneId: String) -> [HueScene] {
        getPinnedScenes(forGroupId: zoneId)
    }

    /// Get count of pinned scenes for a group
    public func getPinnedSceneCount(forGroupId groupId: String) -> Int {
        scenePinning.getPinnedSceneCount(forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Clear all pinned scenes for a specific group
    public func clearPinnedScenes(forGroupId groupId: String) {
        scenePinning.clearPinnedScenes(forGroupId: groupId, bridgeId: connectedBridge?.bridge.id)
    }

    /// Clear ALL pinned scenes across all bridges
    public func clearAllPinnedScenes() {
        scenePinning.clearAllPinnedScenes()
    }

    // MARK: - Local State Updates

    /// Generic local state update for any GroupedLightContainer
    /// Updates grouped lights optimistically after a successful control action
    private func updateLocalGroupState<T: GroupedLightContainer>(
        groupId: String,
        in collection: inout [T],
        on: Bool?,
        brightness: Double?,
        save: () -> Void
    ) {
        guard let index = collection.firstIndex(where: { $0.id == groupId }) else {
            AppLogger.bridge.warning("updateLocalGroupState: \(T.apiGroupType, privacy: .public) \(groupId, privacy: .public) not found in local cache")
            return
        }

        var updatedItem = collection[index]

        // Update grouped lights by recreating the structs (they're immutable)
        if let groupedLights = updatedItem.groupedLights, !groupedLights.isEmpty {
            let updatedGroupedLights = groupedLights.map { light in
                let newOn = on != nil ? HueGroupedLight.GroupedLightOn(on: on!) : light.on
                let newDimming = brightness != nil ? HueGroupedLight.GroupedLightDimming(brightness: brightness!) : light.dimming

                return HueGroupedLight(
                    id: light.id,
                    type: light.type,
                    on: newOn,
                    dimming: newDimming,
                    colorTemperature: light.colorTemperature,
                    color: light.color
                )
            }
            updatedItem.groupedLights = updatedGroupedLights

            if let on = on {
                AppLogger.bridge.debug("updateLocalGroupState: Updated \(T.apiGroupType, privacy: .public) '\(updatedItem.displayName, privacy: .public)' on state to \(on, privacy: .public)")
            }
            if let brightness = brightness {
                AppLogger.bridge.debug("updateLocalGroupState: Updated \(T.apiGroupType, privacy: .public) '\(updatedItem.displayName, privacy: .public)' brightness to \(Int(brightness), privacy: .public)%")
            }
        }

        // Update the item in the array
        collection[index] = updatedItem

        // Save to cache
        save()
    }

    /// Update local room state optimistically after a successful control action
    /// This ensures the list view reflects changes immediately without waiting for a full refresh
    public func updateLocalRoomState(roomId: String, on: Bool? = nil, brightness: Double? = nil) {
        updateLocalGroupState(groupId: roomId, in: &rooms, on: on, brightness: brightness, save: saveRoomsToStorage)
    }

    /// Update local zone state optimistically after a successful control action
    /// This ensures the list view reflects changes immediately without waiting for a full refresh
    public func updateLocalZoneState(zoneId: String, on: Bool? = nil, brightness: Double? = nil) {
        updateLocalGroupState(groupId: zoneId, in: &zones, on: on, brightness: brightness, save: saveZonesToStorage)
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
            AppLogger.bridge.error("fetchGroupedLight: \(error.localizedDescription, privacy: .public)")
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
            AppLogger.bridge.debug("setGroupedLightPower: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(BridgeManagerError.notConnected)
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
            AppLogger.bridge.debug("setGroupedLightBrightness: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(BridgeManagerError.notConnected)
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
            AppLogger.bridge.debug("setGroupedLightPowerAndBrightness: Demo mode - skipping network call")
            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(BridgeManagerError.notConnected)
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
            AppLogger.bridge.debug("turnOffAllLights: Demo mode - updating local state only")

            // Update grouped lights in rooms to reflect off state
            for index in rooms.indices {
                if var groupedLights = rooms[index].groupedLights {
                    for i in groupedLights.indices {
                        groupedLights[i] = HueGroupedLight(
                            id: groupedLights[i].id,
                            type: groupedLights[i].type,
                            on: HueGroupedLight.GroupedLightOn(on: false),
                            dimming: groupedLights[i].dimming,
                            colorTemperature: groupedLights[i].colorTemperature,
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
                            colorTemperature: groupedLights[i].colorTemperature,
                            color: groupedLights[i].color
                        )
                    }
                    zones[index].groupedLights = groupedLights
                }
            }

            return .success(())
        }

        guard currentConnectedBridge != nil else {
            return .failure(BridgeManagerError.notConnected)
        }

        AppLogger.bridge.debug("Turning off all lights...")

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
            AppLogger.bridge.warning("No grouped lights found to turn off")
            return .success(())
        }

        AppLogger.bridge.debug("Found \(groupedLightIds.count, privacy: .public) grouped lights to turn off")
        AppLogger.bridge.debug("Estimated time: ~\(groupedLightIds.count, privacy: .public) seconds (1 group/sec)")

        // Turn off each grouped light using HueAPIService (rate limiting automatically enforced)
        var successCount = 0
        var failureCount = 0

        for groupedLightId in groupedLightIds {
            do {
                try await HueAPIService.shared.setPower(groupedLightId: groupedLightId, on: false)
                successCount += 1
                AppLogger.bridge.debug("Turned off grouped light \(groupedLightId.prefix(8), privacy: .public)... (\(successCount, privacy: .public)/\(groupedLightIds.count, privacy: .public))")
            } catch {
                failureCount += 1
                AppLogger.bridge.error("Failed to turn off grouped light \(groupedLightId.prefix(8), privacy: .public)...: \(error.localizedDescription, privacy: .public)")
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
                        colorTemperature: groupedLights[i].colorTemperature,
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
                        colorTemperature: groupedLights[i].colorTemperature,
                        color: groupedLights[i].color
                    )
                }
                zones[index].groupedLights = groupedLights
            }
        }

        saveRoomsToStorage()
        saveZonesToStorage()

        AppLogger.bridge.info("All lights turned off: \(successCount, privacy: .public) succeeded, \(failureCount, privacy: .public) failed")
        return .success(())
    }

    // MARK: - Keychain Helpers

    private static let keychainService = "com.huedat.bridge"

    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

}
