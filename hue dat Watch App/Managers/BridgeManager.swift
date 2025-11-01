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
enum ConnectionValidationResult {
    case success
    case failure(message: String)
}

// MARK: - Bridge Manager
@MainActor
class BridgeManager: ObservableObject {
    @Published var connectedBridge: BridgeConnectionInfo?
    @Published var showAlert: Bool = false
    @Published var alertMessage: String? = nil
    @Published var isConnectionValidated: Bool = false
    @Published var rooms: [HueRoom] = []
    @Published var zones: [HueZone] = []
    @Published var isLoadingRooms: Bool = false
    @Published var isLoadingZones: Bool = false

    // Event broadcasting for connection validation
    private let connectionValidationSubject = PassthroughSubject<ConnectionValidationResult, Never>()
    var connectionValidationPublisher: AnyPublisher<ConnectionValidationResult, Never> {
        connectionValidationSubject.eraseToAnyPublisher()
    }
    
    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    
    /// Returns the current connected bridge information, or nil if none is connected.
    var currentConnectedBridge: BridgeConnectionInfo? {
        connectedBridge
    }
    
    init() {
        loadConnectedBridge()
    }
    
    func saveConnection(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        let connectionInfo = BridgeConnectionInfo(bridge: bridge, registrationResponse: registrationResponse)
        
        do {
            let data = try JSONEncoder().encode(connectionInfo)
            userDefaults.set(data, forKey: connectedBridgeKey)
            
            // Force synchronize to ensure data is written immediately
            userDefaults.synchronize()
            
            connectedBridge = connectionInfo
            print("✅ Bridge connection saved successfully:")
            print("  - Bridge: \(bridge.displayName) (\(bridge.shortId))")
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
    
    func disconnectBridge() {
        userDefaults.removeObject(forKey: connectedBridgeKey)
        userDefaults.synchronize()
        connectedBridge = nil
        isConnectionValidated = false
        print("🔌 Bridge disconnected and cleared from storage")
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
                print("  - Username: \(connection.username)")
                print("  - ClientKey: \(connection.clientkey ?? "nil")")
                print("  - Connected Date: \(connection.connectedDate)")
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
    
    struct HueRoom: Decodable, Identifiable {
        let id: String
        let type: String
        let metadata: RoomMetadata
        var children: [HueRoomChild]?
        var services: [HueRoomService]?
        var groupedLights: [HueGroupedLight]?
        
        struct RoomMetadata: Decodable {
            let name: String
            let archetype: String
        }
        
        struct HueRoomChild: Decodable {
            let rid: String
            let rtype: String
        }
        
        struct HueRoomService: Decodable {
            let rid: String
            let rtype: String
        }
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
    
    struct HueGroupedLight: Decodable, Identifiable {
        let id: String
        let type: String
        let on: GroupedLightOn?
        let dimming: GroupedLightDimming?
        let color_temperature: GroupedLightColorTemperature?
        let color: GroupedLightColor?
        
        struct GroupedLightOn: Decodable {
            let on: Bool
        }
        
        struct GroupedLightDimming: Decodable {
            let brightness: Double
        }
        
        struct GroupedLightColorTemperature: Decodable {
            let mirek: Int?
            let mirek_valid: Bool?
            let mirek_schema: GroupedLightColorTemperatureSchema?
            
            struct GroupedLightColorTemperatureSchema: Decodable {
                let mirek_minimum: Int
                let mirek_maximum: Int
            }
        }
        
        struct GroupedLightColor: Decodable {
            let xy: GroupedLightColorXY?
            let gamut: GroupedLightColorGamut?
            let gamut_type: String?
            
            struct GroupedLightColorXY: Decodable {
                let x: Double
                let y: Double
            }
            
            struct GroupedLightColorGamut: Decodable {
                let red: GroupedLightColorXY
                let green: GroupedLightColorXY
                let blue: GroupedLightColorXY
            }
        }
    }
    
    // MARK: - Zone API Response Models
    private struct HueZonesResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueZone]
    }
    
    struct HueZone: Decodable, Identifiable {
        let id: String
        let type: String
        let metadata: ZoneMetadata
        var children: [HueZoneChild]?
        var services: [HueZoneService]?
        var groupedLights: [HueGroupedLight]?
        
        struct ZoneMetadata: Decodable {
            let name: String
            let archetype: String
        }
        
        struct HueZoneChild: Decodable {
            let rid: String
            let rtype: String
        }
        
        struct HueZoneService: Decodable {
            let rid: String
            let rtype: String
        }
    }
    
    // MARK: - Individual Zone Response Models
    private struct HueZoneDetailResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueZoneDetail]
    }
    
    private struct HueZoneDetail: Decodable {
        let id: String
        let type: String
        let metadata: HueZone.ZoneMetadata
        let children: [HueZone.HueZoneChild]?
        let services: [HueZone.HueZoneService]?
    }
    
    var isConnected: Bool {
        connectedBridge != nil
    }
    
    /// Validate that the current connection is alive/reachable.
    /// Broadcasts the result via connectionValidationPublisher.
    func validateConnection() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ validateConnection: No connected bridge available")
            isConnectionValidated = false
            connectionValidationSubject.send(.failure(message: "No bridge connection available"))
            return
        }
        isConnectionValidated = false
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ validateConnection: Invalid URL: \(urlString)")
            let errorMessage = "Invalid bridge URL"
            connectionValidationSubject.send(.failure(message: errorMessage))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print(request)
        
        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 validateConnection: HTTP \(http.statusCode)")
            }

            // Attempt to decode Hue API v2 response which has the structure:
            // {"errors": [], "data": []}
            do {
                let response = try JSONDecoder().decode(HueAPIV2Response.self, from: data)
                
                // Check for errors first
                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ validateConnection: Hue API v2 errors: \(errorMessages)")
                    self.isConnectionValidated = false
                    // Publish alert to the UI
                    self.alertMessage = errorMessages
                    self.showAlert = true
                    // Broadcast failure event
                    connectionValidationSubject.send(.failure(message: errorMessages))
                    return
                }
                
                // If no errors and we have data, connection is valid
                if response.errors.isEmpty {
                    print("✅ validateConnection: Success - connection validated with \(response.data.count) data items")
                    self.isConnectionValidated = true
                    // Broadcast success event
                    connectionValidationSubject.send(.success)
                } else {
                    print("ℹ️ validateConnection: No errors but unexpected response structure")
                    self.isConnectionValidated = false
                    let errorMessage = "Unexpected response from bridge"
                    connectionValidationSubject.send(.failure(message: errorMessage))
                }
            } catch {
                // If decoding into the Hue v2 format fails, log raw string for diagnostics
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ validateConnection: Failed to decode v2 response: \(responseString)")
                } else {
                    print("ℹ️ validateConnection: Received non-UTF8 data (\(data.count) bytes)")
                }
                self.isConnectionValidated = false
                let errorMessage = "Invalid response from bridge"
                connectionValidationSubject.send(.failure(message: errorMessage))
            }
        } catch {
            print("❌ validateConnection: Network error: \(error.localizedDescription)")
            self.isConnectionValidated = false
            self.alertMessage = error.localizedDescription
            self.showAlert = true
            // Broadcast failure event
            connectionValidationSubject.send(.failure(message: error.localizedDescription))
        }
    }
    
    /// Retrieve the list of rooms from the connected bridge.
    /// Updates the rooms published property with the results.
    func getRooms() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ getRooms: No connected bridge available")
            rooms = []
            isLoadingRooms = false
            return
        }

        isLoadingRooms = true
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/room"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ getRooms: Invalid URL: \(urlString)")
            rooms = []
            isLoadingRooms = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🏠 getRooms: Requesting rooms from \(urlString)")
        
        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 getRooms: HTTP \(http.statusCode)")
            }

            // Attempt to decode Hue API v2 response for rooms
            do {
                let response = try JSONDecoder().decode(HueRoomsResponse.self, from: data)
                
                // Check for errors first
                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ getRooms: Hue API v2 errors: \(errorMessages)")
                    self.rooms = []
                    // Publish alert to the UI
                    self.alertMessage = errorMessages
                    self.showAlert = true
                    return
                }
                
                // If no errors, get basic rooms first
                if response.errors.isEmpty {
                    print("✅ getRooms: Success - retrieved \(response.data.count) rooms")
                    
                    // Now fetch detailed metadata for each room
                    var enhancedRooms: [HueRoom] = []
                    
                    for room in response.data {
                        print("  - Fetching details for room: \(room.metadata.name) (ID: \(room.id))")
                        
                        // Get detailed room information
                        if let detailedRoom = await fetchRoomDetails(roomId: room.id, session: session) {
                            // Check if room has grouped light services
                            var groupedLights: [HueGroupedLight] = []
                            if let services = detailedRoom.services {
                                let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
                                for service in groupedLightServices {
                                    print("    - Fetching grouped light details for service: \(service.rid)")
                                    if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                                        groupedLights.append(groupedLight)
                                        print("      ✅ Added grouped light details")
                                    } else {
                                        print("      ❌ Failed to fetch grouped light details")
                                    }
                                }
                            }
                            
                            // Merge the detailed information with the basic room
                            let mergedRoom = HueRoom(
                                id: room.id,
                                type: room.type,
                                metadata: room.metadata,
                                children: detailedRoom.children,
                                services: detailedRoom.services,
                                groupedLights: groupedLights.isEmpty ? nil : groupedLights
                            )
                            enhancedRooms.append(mergedRoom)
                            print("    ✅ Enhanced room: \(room.metadata.name)")
                            print("      - Children: \(detailedRoom.children?.count ?? 0)")
                            print("      - Services: \(detailedRoom.services?.count ?? 0)")
                            print("      - Grouped Lights: \(groupedLights.count)")
                        } else {
                            // If we can't get details, use the basic room
                            print("    ⚠️ Using basic room data for: \(room.metadata.name)")
                            enhancedRooms.append(room)
                        }
                    }
                    
                    self.rooms = enhancedRooms
                    print("🏠 getRooms: Completed with \(enhancedRooms.count) enhanced rooms")
                } else {
                    print("ℹ️ getRooms: No errors but unexpected response structure")
                    self.rooms = []
                }
            } catch {
                // If decoding into the Hue rooms format fails, log raw string for diagnostics
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ getRooms: Failed to decode rooms response: \(responseString)")
                } else {
                    print("ℹ️ getRooms: Received non-UTF8 data (\(data.count) bytes)")
                }
                self.rooms = []
            }
        } catch {
            print("❌ getRooms: Network error: \(error.localizedDescription)")
            self.rooms = []
            self.alertMessage = error.localizedDescription
            self.showAlert = true
        }

        isLoadingRooms = false
    }
    
    /// Fetch detailed metadata for a specific room by its ID
    private func fetchRoomDetails(roomId: String, session: URLSession) async -> HueRoomDetail? {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchRoomDetails: No connected bridge available")
            return nil
        }
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/room/\(roomId)"
        
        guard let url = URL(string: urlString) else {
            print("❌ fetchRoomDetails: Invalid URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                print("    🌐 fetchRoomDetails: HTTP \(http.statusCode) for room \(roomId)")
            }
            
            // Decode the detailed room response
            do {
                let detailResponse = try JSONDecoder().decode(HueRoomDetailResponse.self, from: data)
                
                // Check for errors
                if !detailResponse.errors.isEmpty {
                    let errorMessages = detailResponse.errors.map { $0.description }.joined(separator: ", ")
                    print("    ❌ fetchRoomDetails: API errors for room \(roomId): \(errorMessages)")
                    return nil
                }
                
                // Return the first (and should be only) room detail
                return detailResponse.data.first
                
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("    ℹ️ fetchRoomDetails: Failed to decode response for room \(roomId): \(responseString)")
                } else {
                    print("    ℹ️ fetchRoomDetails: Received non-UTF8 data for room \(roomId) (\(data.count) bytes)")
                }
                return nil
            }
            
        } catch {
            print("    ❌ fetchRoomDetails: Network error for room \(roomId): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetch detailed metadata for a specific zone by its ID
    private func fetchZoneDetails(zoneId: String, session: URLSession) async -> HueZoneDetail? {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchZoneDetails: No connected bridge available")
            return nil
        }
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/zone/\(zoneId)"
        
        guard let url = URL(string: urlString) else {
            print("❌ fetchZoneDetails: Invalid URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                print("    🌐 fetchZoneDetails: HTTP \(http.statusCode) for zone \(zoneId)")
            }
            
            // Decode the detailed zone response
            do {
                let detailResponse = try JSONDecoder().decode(HueZoneDetailResponse.self, from: data)
                
                // Check for errors
                if !detailResponse.errors.isEmpty {
                    let errorMessages = detailResponse.errors.map { $0.description }.joined(separator: ", ")
                    print("    ❌ fetchZoneDetails: API errors for zone \(zoneId): \(errorMessages)")
                    return nil
                }
                
                // Return the first (and should be only) zone detail
                return detailResponse.data.first
                
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("    ℹ️ fetchZoneDetails: Failed to decode response for zone \(zoneId): \(responseString)")
                } else {
                    print("    ℹ️ fetchZoneDetails: Received non-UTF8 data for zone \(zoneId) (\(data.count) bytes)")
                }
                return nil
            }
            
        } catch {
            print("    ❌ fetchZoneDetails: Network error for zone \(zoneId): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetch detailed metadata for a specific grouped light by its ID
    private func fetchGroupedLightDetails(groupedLightId: String, session: URLSession) async -> HueGroupedLight? {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchGroupedLightDetails: No connected bridge available")
            return nil
        }
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/grouped_light/\(groupedLightId)"
        
        guard let url = URL(string: urlString) else {
            print("❌ fetchGroupedLightDetails: Invalid URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                print("    🌐 fetchGroupedLightDetails: HTTP \(http.statusCode) for grouped light \(groupedLightId)")
            }
            
            // Decode the grouped light response
            do {
                let lightResponse = try JSONDecoder().decode(HueGroupedLightResponse.self, from: data)
                
                // Check for errors
                if !lightResponse.errors.isEmpty {
                    let errorMessages = lightResponse.errors.map { $0.description }.joined(separator: ", ")
                    print("    ❌ fetchGroupedLightDetails: API errors for grouped light \(groupedLightId): \(errorMessages)")
                    return nil
                }
                
                // Return the first (and should be only) grouped light detail
                return lightResponse.data.first
                
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("    ℹ️ fetchGroupedLightDetails: Failed to decode response for grouped light \(groupedLightId): \(responseString)")
                } else {
                    print("    ℹ️ fetchGroupedLightDetails: Received non-UTF8 data for grouped light \(groupedLightId) (\(data.count) bytes)")
                }
                return nil
            }
            
        } catch {
            print("    ❌ fetchGroupedLightDetails: Network error for grouped light \(groupedLightId): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Retrieve the list of zones from the connected bridge.
    /// Updates the zones published property with the results.
    func getZones() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ getZones: No connected bridge available")
            zones = []
            return
        }
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/zone"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ getZones: Invalid URL: \(urlString)")
            zones = []
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🏢 getZones: Requesting zones from \(urlString)")
        
        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 getZones: HTTP \(http.statusCode)")
            }

            // Attempt to decode Hue API v2 response for zones
            do {
                let response = try JSONDecoder().decode(HueZonesResponse.self, from: data)
                
                // Check for errors first
                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ getZones: Hue API v2 errors: \(errorMessages)")
                    self.zones = []
                    // Publish alert to the UI
                    self.alertMessage = errorMessages
                    self.showAlert = true
                    return
                }
                
                // If no errors, get basic zones first
                if response.errors.isEmpty {
                    print("✅ getZones: Success - retrieved \(response.data.count) zones")
                    
                    // Now fetch detailed metadata for each zone
                    var enhancedZones: [HueZone] = []
                    
                    for zone in response.data {
                        print("  - Fetching details for zone: \(zone.metadata.name) (ID: \(zone.id))")
                        
                        // Get detailed zone information
                        if let detailedZone = await fetchZoneDetails(zoneId: zone.id, session: session) {
                            // Check if zone has grouped light services
                            var groupedLights: [HueGroupedLight] = []
                            if let services = detailedZone.services {
                                let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
                                for service in groupedLightServices {
                                    print("    - Fetching grouped light details for service: \(service.rid)")
                                    if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                                        groupedLights.append(groupedLight)
                                        print("      ✅ Added grouped light details")
                                    } else {
                                        print("      ❌ Failed to fetch grouped light details")
                                    }
                                }
                            }
                            
                            // Merge the detailed information with the basic zone
                            let mergedZone = HueZone(
                                id: zone.id,
                                type: zone.type,
                                metadata: zone.metadata,
                                children: detailedZone.children,
                                services: detailedZone.services,
                                groupedLights: groupedLights.isEmpty ? nil : groupedLights
                            )
                            enhancedZones.append(mergedZone)
                            print("    ✅ Enhanced zone: \(zone.metadata.name)")
                            print("      - Children: \(detailedZone.children?.count ?? 0)")
                            print("      - Services: \(detailedZone.services?.count ?? 0)")
                            print("      - Grouped Lights: \(groupedLights.count)")
                        } else {
                            // If we can't get details, use the basic zone
                            print("    ⚠️ Using basic zone data for: \(zone.metadata.name)")
                            enhancedZones.append(zone)
                        }
                    }
                    
                    self.zones = enhancedZones
                    print("🏢 getZones: Completed with \(enhancedZones.count) enhanced zones")
                } else {
                    print("ℹ️ getZones: No errors but unexpected response structure")
                    self.zones = []
                }
            } catch {
                // If decoding into the Hue zones format fails, log raw string for diagnostics
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ getZones: Failed to decode zones response: \(responseString)")
                } else {
                    print("ℹ️ getZones: Received non-UTF8 data (\(data.count) bytes)")
                }
                self.zones = []
            }
        } catch {
            print("❌ getZones: Network error: \(error.localizedDescription)")
            self.zones = []
            self.alertMessage = error.localizedDescription
            self.showAlert = true
        }
    }
        
}
