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
    @Published var scenes: [HueScene] = []
    @Published var lightCache: [String: HueLight] = [:]  // Shared cache of all lights by ID
    @Published var isLoadingRooms: Bool = false
    @Published var isLoadingZones: Bool = false

    // Event broadcasting for connection validation
    private let connectionValidationSubject = PassthroughSubject<ConnectionValidationResult, Never>()
    var connectionValidationPublisher: AnyPublisher<ConnectionValidationResult, Never> {
        connectionValidationSubject.eraseToAnyPublisher()
    }

    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    private let cachedRoomsKey = "CachedRooms"
    private let cachedZonesKey = "CachedZones"
    private let cachedScenesKey = "CachedScenes"
    private let cachedLightsKey = "CachedLights"

    // Refresh state management
    private var isRefreshing: Bool = false
    
    /// Returns the current connected bridge information, or nil if none is connected.
    var currentConnectedBridge: BridgeConnectionInfo? {
        connectedBridge
    }
    
    init() {
        loadConnectedBridge()
        loadLightsFromStorage()
        loadRoomsFromStorage()
        loadZonesFromStorage()
        loadScenesFromStorage()
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
        userDefaults.removeObject(forKey: cachedRoomsKey)
        userDefaults.removeObject(forKey: cachedZonesKey)
        userDefaults.removeObject(forKey: cachedScenesKey)
        userDefaults.removeObject(forKey: cachedLightsKey)
        userDefaults.synchronize()
        connectedBridge = nil
        isConnectionValidated = false
        rooms = []
        zones = []
        scenes = []
        lightCache = [:]
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

    private func loadLightsFromStorage() {
        guard let data = userDefaults.data(forKey: cachedLightsKey) else {
            print("📂 No cached lights found")
            return
        }

        do {
            let lightsArray = try JSONDecoder().decode([HueLight].self, from: data)
            // Convert array to dictionary by ID
            lightCache = Dictionary(uniqueKeysWithValues: lightsArray.map { ($0.id, $0) })
            print("✅ Loaded \(lightCache.count) cached lights from storage")
        } catch {
            print("❌ Failed to load cached lights: \(error)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: cachedLightsKey)
        }
    }

    private func saveLightsToStorage() {
        do {
            // Convert dictionary to array for encoding
            let lightsArray = Array(lightCache.values)
            let data = try JSONEncoder().encode(lightsArray)
            userDefaults.set(data, forKey: cachedLightsKey)
            print("💾 Saved \(lightCache.count) lights to storage (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save lights to storage: \(error)")
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
    
    struct HueRoom: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let type: String
        let metadata: RoomMetadata
        var children: [HueRoomChild]?
        var services: [HueRoomService]?
        var groupedLights: [HueGroupedLight]?
        var lights: [HueLight]?

        struct RoomMetadata: Codable, Equatable, Hashable {
            let name: String
            let archetype: String
        }

        struct HueRoomChild: Codable, Equatable, Hashable {
            let rid: String
            let rtype: String
        }

        struct HueRoomService: Codable, Equatable, Hashable {
            let rid: String
            let rtype: String
        }

        // Custom Equatable implementation for efficient comparison
        static func == (lhs: HueRoom, rhs: HueRoom) -> Bool {
            lhs.id == rhs.id &&
            lhs.metadata == rhs.metadata &&
            lhs.groupedLights == rhs.groupedLights
        }

        // Custom Hashable implementation
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
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

    struct HueGroupedLight: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let type: String
        let on: GroupedLightOn?
        let dimming: GroupedLightDimming?
        let color_temperature: GroupedLightColorTemperature?
        let color: GroupedLightColor?

        struct GroupedLightOn: Codable, Equatable, Hashable {
            let on: Bool
        }

        struct GroupedLightDimming: Codable, Equatable, Hashable {
            let brightness: Double
        }

        struct GroupedLightColorTemperature: Codable, Equatable, Hashable {
            let mirek: Int?
            let mirek_valid: Bool?
            let mirek_schema: GroupedLightColorTemperatureSchema?

            struct GroupedLightColorTemperatureSchema: Codable, Equatable, Hashable {
                let mirek_minimum: Int
                let mirek_maximum: Int
            }
        }

        struct GroupedLightColor: Codable, Equatable, Hashable {
            let xy: GroupedLightColorXY?
            let gamut: GroupedLightColorGamut?
            let gamut_type: String?

            struct GroupedLightColorXY: Codable, Equatable, Hashable {
                let x: Double
                let y: Double
            }

            struct GroupedLightColorGamut: Codable, Equatable, Hashable {
                let red: GroupedLightColorXY
                let green: GroupedLightColorXY
                let blue: GroupedLightColorXY
            }
        }

        // Custom Equatable implementation
        static func == (lhs: HueGroupedLight, rhs: HueGroupedLight) -> Bool {
            lhs.id == rhs.id &&
            lhs.on?.on == rhs.on?.on &&
            lhs.dimming?.brightness == rhs.dimming?.brightness &&
            lhs.color_temperature?.mirek == rhs.color_temperature?.mirek &&
            lhs.color?.xy?.x == rhs.color?.xy?.x &&
            lhs.color?.xy?.y == rhs.color?.xy?.y
        }

        // Custom Hashable implementation
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Individual Light API Response Models
    private struct HueLightResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueLight]
    }

    struct HueLight: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let type: String
        let metadata: LightMetadata?
        let on: LightOn?
        let dimming: LightDimming?
        let color_temperature: LightColorTemperature?
        let color: LightColor?

        struct LightMetadata: Codable, Equatable, Hashable {
            let name: String
            let archetype: String?
        }

        struct LightOn: Codable, Equatable, Hashable {
            let on: Bool
        }

        struct LightDimming: Codable, Equatable, Hashable {
            let brightness: Double
        }

        struct LightColorTemperature: Codable, Equatable, Hashable {
            let mirek: Int?
            let mirek_valid: Bool?
        }

        struct LightColor: Codable, Equatable, Hashable {
            let xy: LightColorXY?
            let gamut: LightColorGamut?
            let gamut_type: String?

            struct LightColorXY: Codable, Equatable, Hashable {
                let x: Double
                let y: Double
            }

            struct LightColorGamut: Codable, Equatable, Hashable {
                let red: LightColorXY
                let green: LightColorXY
                let blue: LightColorXY
            }
        }

        // Custom Equatable implementation
        static func == (lhs: HueLight, rhs: HueLight) -> Bool {
            lhs.id == rhs.id &&
            lhs.on?.on == rhs.on?.on &&
            lhs.dimming?.brightness == rhs.dimming?.brightness &&
            lhs.color_temperature?.mirek == rhs.color_temperature?.mirek &&
            lhs.color?.xy?.x == rhs.color?.xy?.x &&
            lhs.color?.xy?.y == rhs.color?.xy?.y
        }

        // Custom Hashable implementation
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    // MARK: - Zone API Response Models
    private struct HueZonesResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueZone]
    }
    
    struct HueZone: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let type: String
        let metadata: ZoneMetadata
        var children: [HueZoneChild]?
        var services: [HueZoneService]?
        var groupedLights: [HueGroupedLight]?
        var lights: [HueLight]?

        struct ZoneMetadata: Codable, Equatable, Hashable {
            let name: String
            let archetype: String
        }

        struct HueZoneChild: Codable, Equatable, Hashable {
            let rid: String
            let rtype: String
        }

        struct HueZoneService: Codable, Equatable, Hashable {
            let rid: String
            let rtype: String
        }

        // Custom Equatable implementation for efficient comparison
        static func == (lhs: HueZone, rhs: HueZone) -> Bool {
            lhs.id == rhs.id &&
            lhs.metadata == rhs.metadata &&
            lhs.groupedLights == rhs.groupedLights
        }

        // Custom Hashable implementation
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
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

    // MARK: - Scene API Response Models
    private struct HueScenesResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueScene]
    }

    // MARK: - Light API Response Models
    private struct HueLightsResponse: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueLight]
    }
    
    var isConnected: Bool {
        connectedBridge != nil
    }
    
    /// Print detailed light information for debugging purposes
    func printDetailedLightInfo(for roomOrZone: String, groupedLights: [HueGroupedLight]?, individualLights: [HueLight]? = nil) {
        print("🔍 DEBUG: \(roomOrZone) - Light Details:")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Print grouped lights section
        if let lights = groupedLights, !lights.isEmpty {
            print("\n📦 GROUPED LIGHTS (Aggregated State):")
            print("   Total grouped lights: \(lights.count)")

            for (index, light) in lights.enumerated() {
                print("\n   Grouped Light \(index + 1):")
                print("     • ID: \(light.id)")
                print("     • Type: \(light.type)")

                // Power state
                if let powerState = light.on?.on {
                    print("     • Power: \(powerState ? "ON" : "OFF")")
                } else {
                    print("     • Power: Unknown")
                }

                // Brightness
                if let brightness = light.dimming?.brightness {
                    print("     • Brightness: \(Int(brightness))% (\(brightness))")
                } else {
                    print("     • Brightness: Not available")
                }

                // Color temperature
                if let colorTemp = light.color_temperature {
                    if let mirek = colorTemp.mirek {
                        let kelvin = 1000000 / mirek
                        print("     • Color Temperature: \(mirek) mirek (~\(kelvin)K)")
                        print("     • CT Valid: \(colorTemp.mirek_valid ?? false)")
                    } else {
                        print("     • Color Temperature: Not set")
                    }

                    // Color temperature schema (min/max range)
                    if let schema = colorTemp.mirek_schema {
                        let minKelvin = 1000000 / schema.mirek_maximum
                        let maxKelvin = 1000000 / schema.mirek_minimum
                        print("     • CT Range: \(schema.mirek_minimum)-\(schema.mirek_maximum) mirek (~\(maxKelvin)K-\(minKelvin)K)")
                    }
                } else {
                    print("     • Color Temperature: Not available")
                }

                // Color (XY coordinates)
                if let color = light.color {
                    if let xy = color.xy {
                        print("     • Color XY: (\(String(format: "%.4f", xy.x)), \(String(format: "%.4f", xy.y)))")
                    } else {
                        print("     • Color XY: Not set")
                    }

                    if let gamutType = color.gamut_type {
                        print("     • Color Gamut: \(gamutType)")
                    }

                    if let gamut = color.gamut {
                        print("     • Gamut Red: (\(String(format: "%.4f", gamut.red.x)), \(String(format: "%.4f", gamut.red.y)))")
                        print("     • Gamut Green: (\(String(format: "%.4f", gamut.green.x)), \(String(format: "%.4f", gamut.green.y)))")
                        print("     • Gamut Blue: (\(String(format: "%.4f", gamut.blue.x)), \(String(format: "%.4f", gamut.blue.y)))")
                    }
                } else {
                    print("     • Color: Not available")
                }
            }

            // Summary statistics for grouped lights
            let lightsOn = lights.filter { $0.on?.on == true }
            let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()
            let averageColorTemp = lights.compactMap { $0.color_temperature?.mirek }.compactMap { $0 }.average().map { Int($0) }

            print("\n   📊 Grouped Lights Summary:")
            print("     • Lights on: \(lightsOn.count)/\(lights.count)")
            if let avgBrightness = averageBrightness {
                print("     • Average brightness: \(Int(avgBrightness))%")
            }
            if let avgColorTemp = averageColorTemp {
                let kelvin = 1000000 / avgColorTemp
                print("     • Average color temp: \(avgColorTemp) mirek (~\(kelvin)K)")
            }
        } else {
            print("\n📦 GROUPED LIGHTS: None found")
        }

        // Print individual lights section
        if let individualLights = individualLights, !individualLights.isEmpty {
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("💡 INDIVIDUAL LIGHTS (Actual Light Colors):")
            print("   Total individual lights: \(individualLights.count)")

            for (index, light) in individualLights.enumerated() {
                print("\n   Individual Light \(index + 1):")
                print("     • ID: \(light.id)")
                print("     • Type: \(light.type)")

                // Name
                if let name = light.metadata?.name {
                    print("     • Name: \"\(name)\"")
                }

                // Power state
                if let powerState = light.on?.on {
                    print("     • Power: \(powerState ? "ON" : "OFF")")
                } else {
                    print("     • Power: Unknown")
                }

                // Brightness
                if let brightness = light.dimming?.brightness {
                    print("     • Brightness: \(Int(brightness))% (\(brightness))")
                } else {
                    print("     • Brightness: Not available")
                }

                // Color temperature
                if let colorTemp = light.color_temperature {
                    if let mirek = colorTemp.mirek {
                        let kelvin = 1000000 / mirek
                        print("     • Color Temperature: \(mirek) mirek (~\(kelvin)K)")
                        print("     • CT Valid: \(colorTemp.mirek_valid ?? false)")
                    } else {
                        print("     • Color Temperature: Not set")
                    }
                } else {
                    print("     • Color Temperature: Not available")
                }

                // Color (XY coordinates)
                if let color = light.color {
                    if let xy = color.xy {
                        print("     • Color XY: (\(String(format: "%.4f", xy.x)), \(String(format: "%.4f", xy.y)))")

                        // Convert to RGB and display
                        let brightness = light.dimming?.brightness ?? 100.0
                        let rgbColor = xyToRGB(x: xy.x, y: xy.y, brightness: brightness)

                        // Get RGB components (approximation for display)
                        var red: CGFloat = 0
                        var green: CGFloat = 0
                        var blue: CGFloat = 0
                        var alpha: CGFloat = 0

                        #if canImport(UIKit)
                        UIColor(rgbColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        #endif

                        let r = Int(red * 255)
                        let g = Int(green * 255)
                        let b = Int(blue * 255)
                        let hexString = String(format: "#%02X%02X%02X", r, g, b)

                        print("     • RGB Color: \(hexString) (R:\(r), G:\(g), B:\(b))")
                    } else {
                        print("     • Color XY: Not set")
                    }

                    if let gamutType = color.gamut_type {
                        print("     • Color Gamut: \(gamutType)")
                    }
                } else if let colorTemp = light.color_temperature, let mirek = colorTemp.mirek {
                    // If no XY color but has color temp, convert mirek to RGB
                    let brightness = light.dimming?.brightness ?? 100.0
                    let rgbColor = mirekToRGB(mirek: mirek, brightness: brightness)

                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    var alpha: CGFloat = 0

                    #if canImport(UIKit)
                    UIColor(rgbColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    #endif

                    let r = Int(red * 255)
                    let g = Int(green * 255)
                    let b = Int(blue * 255)
                    let hexString = String(format: "#%02X%02X%02X", r, g, b)

                    print("     • RGB Color (from temp): \(hexString) (R:\(r), G:\(g), B:\(b))")
                } else {
                    print("     • Color: Not available")
                }
            }

            // Summary statistics for individual lights
            let lightsOn = individualLights.filter { $0.on?.on == true }
            let averageBrightness = individualLights.compactMap { $0.dimming?.brightness }.average()
            let averageColorTemp = individualLights.compactMap { $0.color_temperature?.mirek }.average().map { Int($0) }

            // Calculate average color using existing utility
            let averageColor = averageColorFromLights(individualLights)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            #if canImport(UIKit)
            UIColor(averageColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            #endif

            let r = Int(red * 255)
            let g = Int(green * 255)
            let b = Int(blue * 255)
            let hexString = String(format: "#%02X%02X%02X", r, g, b)

            print("\n   📊 Individual Lights Summary:")
            print("     • Lights on: \(lightsOn.count)/\(individualLights.count)")
            if let avgBrightness = averageBrightness {
                print("     • Average brightness: \(Int(avgBrightness))%")
            }
            if let avgColorTemp = averageColorTemp {
                let kelvin = 1000000 / avgColorTemp
                print("     • Average color temp: \(avgColorTemp) mirek (~\(kelvin)K)")
            }
            print("     • Average RGB Color: \(hexString) (R:\(r), G:\(g), B:\(b))")
        } else if individualLights != nil {
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("💡 INDIVIDUAL LIGHTS: None found")
        }

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 DEBUG: End of light details for \(roomOrZone)\n")
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
                                groupedLights: groupedLights.isEmpty ? nil : groupedLights,
                                lights: nil // Will be enriched next
                            )

                            // Enrich with individual light details
                            let enrichedRoom = await enrichRoomWithLights(room: mergedRoom, session: session)
                            enhancedRooms.append(enrichedRoom)
                            print("    ✅ Enhanced room: \(room.metadata.name)")
                            print("      - Children: \(detailedRoom.children?.count ?? 0)")
                            print("      - Services: \(detailedRoom.services?.count ?? 0)")
                            print("      - Grouped Lights: \(groupedLights.count)")
                            print("      - Individual Lights: \(enrichedRoom.lights?.count ?? 0)")
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

    /// Refresh a single room by fetching its latest data from the bridge.
    /// Updates only the specified room in the rooms array.
    func refreshRoom(roomId: String) async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ refreshRoom: No connected bridge available")
            return
        }

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        print("🔄 refreshRoom: Fetching details for room ID: \(roomId)")

        // Get detailed room information
        guard let detailedRoom = await fetchRoomDetails(roomId: roomId, session: session) else {
            print("❌ refreshRoom: Failed to fetch room details")
            return
        }

        // Fetch grouped light details
        var groupedLights: [HueGroupedLight] = []
        if let services = detailedRoom.services {
            let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
            for service in groupedLightServices {
                if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                    groupedLights.append(groupedLight)
                }
            }
        }

        // Preserve existing lights array (only fetch lights on navigation, not on refresh)
        let existingLights = rooms.first(where: { $0.id == roomId })?.lights

        // Create the updated room
        let updatedRoom = HueRoom(
            id: detailedRoom.id,
            type: detailedRoom.type,
            metadata: detailedRoom.metadata,
            children: detailedRoom.children,
            services: detailedRoom.services,
            groupedLights: groupedLights.isEmpty ? nil : groupedLights,
            lights: existingLights
        )

        // Update the specific room in the array
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            rooms[index] = updatedRoom
            print("✅ refreshRoom: Updated room: \(detailedRoom.metadata.name)")
        } else {
            print("⚠️ refreshRoom: Room not found in array, appending")
            rooms.append(updatedRoom)
        }
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

    /// Fetch detailed metadata for a specific individual light by its ID
    private func fetchLightDetails(lightId: String, session: URLSession) async -> HueLight? {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchLightDetails: No connected bridge available")
            return nil
        }

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/light/\(lightId)"

        guard let url = URL(string: urlString) else {
            print("❌ fetchLightDetails: Invalid URL: \(urlString)")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("      🌐 fetchLightDetails: HTTP \(http.statusCode) for light \(lightId)")
            }

            // Decode the individual light response
            do {
                let lightResponse = try JSONDecoder().decode(HueLightResponse.self, from: data)

                // Check for errors
                if !lightResponse.errors.isEmpty {
                    let errorMessages = lightResponse.errors.map { $0.description }.joined(separator: ", ")
                    print("      ❌ fetchLightDetails: API errors for light \(lightId): \(errorMessages)")
                    return nil
                }

                // Return the first (and should be only) light detail
                return lightResponse.data.first

            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("      ℹ️ fetchLightDetails: Failed to decode response for light \(lightId): \(responseString)")
                } else {
                    print("      ℹ️ fetchLightDetails: Received non-UTF8 data for light \(lightId) (\(data.count) bytes)")
                }
                return nil
            }

        } catch {
            print("      ❌ fetchLightDetails: Network error for light \(lightId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Enrich a room with individual light details by fetching each light referenced in children
    private func enrichRoomWithLights(room: HueRoom, session: URLSession) async -> HueRoom {
        guard let children = room.children else {
            print("    ℹ️ enrichRoomWithLights: Room '\(room.metadata.name)' has no children")
            return room
        }

        // Debug: show all child types
        let childTypes = children.map { $0.rtype }.joined(separator: ", ")
        print("    📋 enrichRoomWithLights: Room '\(room.metadata.name)' has children types: [\(childTypes)]")

        // Filter for light children only
        let lightChildren = children.filter { $0.rtype == "light" }
        guard !lightChildren.isEmpty else {
            print("    ℹ️ enrichRoomWithLights: Room '\(room.metadata.name)' has no light children (has \(children.count) children of other types)")
            return room
        }

        print("    💡 enrichRoomWithLights: Fetching \(lightChildren.count) individual lights for room '\(room.metadata.name)'")
        var lights: [HueLight] = []

        for child in lightChildren {
            if let light = await fetchLightDetails(lightId: child.rid, session: session) {
                lights.append(light)
                print("      ✅ Added light: \(light.metadata?.name ?? "Unknown") (ID: \(light.id))")
            } else {
                print("      ❌ Failed to fetch light with ID: \(child.rid)")
            }
        }

        // Return room with enriched light data
        return HueRoom(
            id: room.id,
            type: room.type,
            metadata: room.metadata,
            children: room.children,
            services: room.services,
            groupedLights: room.groupedLights,
            lights: lights.isEmpty ? nil : lights
        )
    }

    /// Enrich a zone with individual light details by fetching each light referenced in children
    private func enrichZoneWithLights(zone: HueZone, session: URLSession) async -> HueZone {
        guard let children = zone.children else {
            print("    ℹ️ enrichZoneWithLights: Zone '\(zone.metadata.name)' has no children")
            return zone
        }

        // Debug: show all child types
        let childTypes = children.map { $0.rtype }.joined(separator: ", ")
        print("    📋 enrichZoneWithLights: Zone '\(zone.metadata.name)' has children types: [\(childTypes)]")

        // Filter for light children only
        let lightChildren = children.filter { $0.rtype == "light" }
        guard !lightChildren.isEmpty else {
            print("    ℹ️ enrichZoneWithLights: Zone '\(zone.metadata.name)' has no light children (has \(children.count) children of other types)")
            return zone
        }

        print("    💡 enrichZoneWithLights: Fetching \(lightChildren.count) individual lights for zone '\(zone.metadata.name)'")
        var lights: [HueLight] = []

        for child in lightChildren {
            if let light = await fetchLightDetails(lightId: child.rid, session: session) {
                lights.append(light)
                print("      ✅ Added light: \(light.metadata?.name ?? "Unknown") (ID: \(light.id))")
            } else {
                print("      ❌ Failed to fetch light with ID: \(child.rid)")
            }
        }

        // Return zone with enriched light data
        return HueZone(
            id: zone.id,
            type: zone.type,
            metadata: zone.metadata,
            children: zone.children,
            services: zone.services,
            groupedLights: zone.groupedLights,
            lights: lights.isEmpty ? nil : lights
        )
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
                                groupedLights: groupedLights.isEmpty ? nil : groupedLights,
                                lights: nil // Will be enriched next
                            )

                            // Enrich with individual light details
                            let enrichedZone = await enrichZoneWithLights(zone: mergedZone, session: session)
                            enhancedZones.append(enrichedZone)
                            print("    ✅ Enhanced zone: \(zone.metadata.name)")
                            print("      - Children: \(detailedZone.children?.count ?? 0)")
                            print("      - Services: \(detailedZone.services?.count ?? 0)")
                            print("      - Grouped Lights: \(groupedLights.count)")
                            print("      - Individual Lights: \(enrichedZone.lights?.count ?? 0)")
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

    /// Refresh a single zone by fetching its latest data from the bridge.
    /// Updates only the specified zone in the zones array.
    func refreshZone(zoneId: String) async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ refreshZone: No connected bridge available")
            return
        }

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        print("🔄 refreshZone: Fetching details for zone ID: \(zoneId)")

        // Get detailed zone information
        guard let detailedZone = await fetchZoneDetails(zoneId: zoneId, session: session) else {
            print("❌ refreshZone: Failed to fetch zone details")
            return
        }

        // Fetch grouped light details
        var groupedLights: [HueGroupedLight] = []
        if let services = detailedZone.services {
            let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
            for service in groupedLightServices {
                if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                    groupedLights.append(groupedLight)
                }
            }
        }

        // Preserve existing lights array (only fetch lights on navigation, not on refresh)
        let existingLights = zones.first(where: { $0.id == zoneId })?.lights

        // Create the updated zone
        let updatedZone = HueZone(
            id: detailedZone.id,
            type: detailedZone.type,
            metadata: detailedZone.metadata,
            children: detailedZone.children,
            services: detailedZone.services,
            groupedLights: groupedLights.isEmpty ? nil : groupedLights,
            lights: existingLights
        )

        // Update the specific zone in the array
        if let index = zones.firstIndex(where: { $0.id == zoneId }) {
            zones[index] = updatedZone
            print("✅ refreshZone: Updated zone: \(detailedZone.metadata.name)")
        } else {
            print("⚠️ refreshZone: Zone not found in array, appending")
            zones.append(updatedZone)
        }
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
    func colorForLight(_ light: HueLight) -> Color? {
        let isOn = light.on?.on ?? false
        let brightness = light.dimming?.brightness ?? 0.0

        // If light is off, return very dim version
        if !isOn {
            // Use last known color if available, otherwise gray
            if let xy = light.color?.xy {
                return xyToRGB(x: xy.x, y: xy.y, brightness: brightness * 0.1) // 10% of brightness
            } else if let mirek = light.color_temperature?.mirek {
                return mirekToRGB(mirek: mirek, brightness: brightness * 0.1)
            } else {
                // Default to very dim gray
                return Color(red: 0.05, green: 0.05, blue: 0.05)
            }
        }

        // Light is on - check if it has color
        if let xy = light.color?.xy {
            return xyToRGB(x: xy.x, y: xy.y, brightness: brightness)
        } else if let mirek = light.color_temperature?.mirek {
            return mirekToRGB(mirek: mirek, brightness: brightness)
        } else {
            // No color data, return white at current brightness
            let b = brightness / 100.0
            return Color(red: b, green: b, blue: b)
        }
    }

    // MARK: - Background Refresh Management

    /// Set the active detail for targeted refresh
    /// Refresh all rooms and zones data
    private func refreshAllData() async {
        guard !isRefreshing else {
            print("⏭️ Skipping refresh - already in progress")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        print("🔄 Refreshing all data")

        // Fetch all lights first (single API call)
        await fetchAllLights()

        async let roomsRefresh: Void = refreshRoomsData()
        async let zonesRefresh: Void = refreshZonesData()

        // Wait for both to complete
        _ = await (roomsRefresh, zonesRefresh)
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

            // Fetch updated data for each room
            var updatedRooms: [HueRoom] = []

            for basicRoom in response.data {
                // Get detailed room information
                if let detailedRoom = await fetchRoomDetails(roomId: basicRoom.id, session: session) {
                    // Fetch grouped lights
                    var groupedLights: [HueGroupedLight] = []
                    if let services = detailedRoom.services {
                        let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
                        for service in groupedLightServices {
                            if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                                groupedLights.append(groupedLight)
                            }
                        }
                    }

                    // Preserve existing lights array (only refresh on navigation)
                    let existingLights = rooms.first(where: { $0.id == basicRoom.id })?.lights

                    let updatedRoom = HueRoom(
                        id: detailedRoom.id,
                        type: detailedRoom.type,
                        metadata: detailedRoom.metadata,
                        children: detailedRoom.children,
                        services: detailedRoom.services,
                        groupedLights: groupedLights.isEmpty ? nil : groupedLights,
                        lights: existingLights
                    )

                    updatedRooms.append(updatedRoom)
                }
            }

            // Smart update - merge with existing data
            smartUpdateRooms(with: updatedRooms)

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

            // Fetch updated data for each zone
            var updatedZones: [HueZone] = []

            for basicZone in response.data {
                // Get detailed zone information
                if let detailedZone = await fetchZoneDetails(zoneId: basicZone.id, session: session) {
                    // Fetch grouped lights
                    var groupedLights: [HueGroupedLight] = []
                    if let services = detailedZone.services {
                        let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
                        for service in groupedLightServices {
                            if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                                groupedLights.append(groupedLight)
                            }
                        }
                    }

                    // Preserve existing lights array (only refresh on navigation)
                    let existingLights = zones.first(where: { $0.id == basicZone.id })?.lights

                    let updatedZone = HueZone(
                        id: detailedZone.id,
                        type: detailedZone.type,
                        metadata: detailedZone.metadata,
                        children: detailedZone.children,
                        services: detailedZone.services,
                        groupedLights: groupedLights.isEmpty ? nil : groupedLights,
                        lights: existingLights
                    )

                    updatedZones.append(updatedZone)
                }
            }

            // Smart update - merge with existing data
            smartUpdateZones(with: updatedZones)

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
        await refreshAllData()
    }

    /// Refresh a single room immediately - optimized for fast UI updates after control actions
    func refreshSingleRoom(roomId: String) async {
        print("⚡ Fast refresh for room: \(roomId)")

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // Fetch detailed room information
        guard let detailedRoom = await fetchRoomDetails(roomId: roomId, session: session) else {
            print("❌ Failed to fetch room details for: \(roomId)")
            return
        }

        // Fetch grouped lights
        var groupedLights: [HueGroupedLight] = []
        if let services = detailedRoom.services {
            let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
            for service in groupedLightServices {
                if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                    groupedLights.append(groupedLight)
                }
            }
        }

        // Fetch individual lights
        var lights: [HueLight] = []
        if let children = detailedRoom.children {
            let lightChildren = children.filter { $0.rtype == "light" }
            for child in lightChildren {
                if let light = await fetchLightDetails(lightId: child.rid, session: session) {
                    lights.append(light)
                }
            }
        }

        // Create updated room
        let updatedRoom = HueRoom(
            id: detailedRoom.id,
            type: detailedRoom.type,
            metadata: detailedRoom.metadata,
            children: detailedRoom.children,
            services: detailedRoom.services,
            groupedLights: groupedLights.isEmpty ? nil : groupedLights,
            lights: lights.isEmpty ? nil : lights
        )

        // Update just this room in the array without affecting other rooms
        updateSingleRoom(updatedRoom)
        print("✅ Room \(roomId) refreshed")
    }

    /// Refresh a single zone immediately - optimized for fast UI updates after control actions
    func refreshSingleZone(zoneId: String) async {
        print("⚡ Fast refresh for zone: \(zoneId)")

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // Fetch detailed zone information
        guard let detailedZone = await fetchZoneDetails(zoneId: zoneId, session: session) else {
            print("❌ Failed to fetch zone details for: \(zoneId)")
            return
        }

        // Fetch grouped lights
        var groupedLights: [HueGroupedLight] = []
        if let services = detailedZone.services {
            let groupedLightServices = services.filter { $0.rtype == "grouped_light" }
            for service in groupedLightServices {
                if let groupedLight = await fetchGroupedLightDetails(groupedLightId: service.rid, session: session) {
                    groupedLights.append(groupedLight)
                }
            }
        }

        // Fetch individual lights
        var lights: [HueLight] = []
        if let children = detailedZone.children {
            let lightChildren = children.filter { $0.rtype == "light" }
            for child in lightChildren {
                if let light = await fetchLightDetails(lightId: child.rid, session: session) {
                    lights.append(light)
                }
            }
        }

        // Create updated zone
        let updatedZone = HueZone(
            id: detailedZone.id,
            type: detailedZone.type,
            metadata: detailedZone.metadata,
            children: detailedZone.children,
            services: detailedZone.services,
            groupedLights: groupedLights.isEmpty ? nil : groupedLights,
            lights: lights.isEmpty ? nil : lights
        )

        // Update just this zone in the array without affecting other zones
        updateSingleZone(updatedZone)
        print("✅ Zone \(zoneId) refreshed")
    }

    // MARK: - Scene Management

    /// Fetch all scenes from the connected bridge
    func fetchScenes() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchScenes: No connected bridge available")
            scenes = []
            return
        }

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/scene"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ fetchScenes: Invalid URL: \(urlString)")
            scenes = []
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("🎬 fetchScenes: Requesting scenes from \(urlString)")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 fetchScenes: HTTP \(http.statusCode)")
            }

            // Decode Hue API v2 response for scenes
            do {
                let response = try JSONDecoder().decode(HueScenesResponse.self, from: data)

                // Check for errors first
                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ fetchScenes: Hue API v2 errors: \(errorMessages)")
                    self.scenes = []
                    return
                }

                // If no errors, update scenes
                if response.errors.isEmpty {
                    self.scenes = response.data
                    saveScenesToStorage()
                    print("✅ fetchScenes: Success - retrieved \(response.data.count) scenes")
                } else {
                    print("ℹ️ fetchScenes: No errors but unexpected response structure")
                    self.scenes = []
                }
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ fetchScenes: Failed to decode scenes response: \(responseString)")
                } else {
                    print("ℹ️ fetchScenes: Received non-UTF8 data (\(data.count) bytes)")
                }
                self.scenes = []
            }
        } catch {
            print("❌ fetchScenes: Network error: \(error.localizedDescription)")
            self.scenes = []
        }
    }

    /// Fetch scenes for a specific room
    func fetchScenes(forRoomId roomId: String) async -> [HueScene] {
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
    func fetchScenes(forZoneId zoneId: String) async -> [HueScene] {
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
    func activateScene(_ sceneId: String) async -> Result<Void, Error> {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ activateScene: No connected bridge available")
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No bridge connection available"]))
        }

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/scene/\(sceneId)"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ activateScene: Invalid URL: \(urlString)")
            return .failure(NSError(domain: "BridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Scene activation payload
        let payload: [String: Any] = [
            "recall": [
                "action": "active"
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 activateScene: HTTP \(http.statusCode)")
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("🎬 activateScene response: \(responseString)")
            }

            // Parse response to check for errors
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               !errors.isEmpty {
                let errorDesc = errors.first?["description"] as? String ?? "Unknown error"
                return .failure(NSError(domain: "HueBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: errorDesc]))
            }

            print("✅ activateScene: Successfully activated scene \(sceneId)")
            return .success(())
        } catch {
            print("❌ activateScene: Network error: \(error.localizedDescription)")
            return .failure(error)
        }
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
    func extractColorsFromScene(_ scene: HueScene) -> [Color] {
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

    // MARK: - Light Cache Management

    /// Fetch all lights in a single API call and cache them
    func fetchAllLights() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ fetchAllLights: No connected bridge available")
            return
        }

        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource/light"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ fetchAllLights: Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("💡 fetchAllLights: Requesting all lights from \(urlString)")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 fetchAllLights: HTTP \(http.statusCode)")
            }

            do {
                let response = try JSONDecoder().decode(HueLightsResponse.self, from: data)

                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ fetchAllLights: Hue API v2 errors: \(errorMessages)")
                    return
                }

                // Convert array to dictionary by ID
                lightCache = Dictionary(uniqueKeysWithValues: response.data.map { ($0.id, $0) })
                saveLightsToStorage()
                print("✅ fetchAllLights: Success - cached \(lightCache.count) lights")

            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ fetchAllLights: Failed to decode response: \(responseString)")
                } else {
                    print("ℹ️ fetchAllLights: Received non-UTF8 data (\(data.count) bytes)")
                }
            }
        } catch {
            print("❌ fetchAllLights: Network error: \(error.localizedDescription)")
        }
    }

    /// Get lights for a room from the cache
    func getLightsForRoom(_ room: HueRoom) -> [HueLight] {
        guard let lightChildren = room.children?.filter({ $0.rtype == "light" }) else {
            return []
        }

        let lights = lightChildren.compactMap { child -> HueLight? in
            lightCache[child.rid]
        }

        print("💡 getLightsForRoom: Retrieved \(lights.count) lights for room '\(room.metadata.name)' from cache")
        return lights
    }

    /// Get lights for a zone from the cache
    func getLightsForZone(_ zone: HueZone) -> [HueLight] {
        guard let lightChildren = zone.children?.filter({ $0.rtype == "light" }) else {
            return []
        }

        let lights = lightChildren.compactMap { child -> HueLight? in
            lightCache[child.rid]
        }

        print("💡 getLightsForZone: Retrieved \(lights.count) lights for zone '\(zone.metadata.name)' from cache")
        return lights
    }

    /// Extract colors from an array of lights (fallback when no scene is active)
    func extractColorsFromLights(_ lights: [HueLight]) -> [Color] {
        let colors = lights.compactMap { light -> Color? in
            colorForLight(light)
        }

        print("🎨 extractColorsFromLights: Extracted \(colors.count) colors from \(lights.count) lights")
        return colors
    }

    /// Calculate average color from an array of lights
    func averageColorFromLights(_ lights: [HueLight]) -> Color {
        let colors = extractColorsFromLights(lights)

        guard !colors.isEmpty else {
            print("🎨 averageColorFromLights: No colors found, returning gray")
            return .gray
        }

        // Convert SwiftUI Colors to RGB components and average them
        var totalRed: CGFloat = 0
        var totalGreen: CGFloat = 0
        var totalBlue: CGFloat = 0
        var validColors = 0

        for color in colors {
            // Use UIColor to extract RGB components
            #if os(watchOS)
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                totalRed += red
                totalGreen += green
                totalBlue += blue
                validColors += 1
            }
            #endif
        }

        guard validColors > 0 else {
            print("🎨 averageColorFromLights: Could not extract RGB, returning gray")
            return .gray
        }

        let avgRed = totalRed / CGFloat(validColors)
        let avgGreen = totalGreen / CGFloat(validColors)
        let avgBlue = totalBlue / CGFloat(validColors)

        print("🎨 averageColorFromLights: Averaged \(validColors) colors -> RGB(\(avgRed), \(avgGreen), \(avgBlue))")
        return Color(red: avgRed, green: avgGreen, blue: avgBlue)
    }

}
