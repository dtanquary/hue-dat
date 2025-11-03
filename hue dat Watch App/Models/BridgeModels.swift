//
//  BridgeModels.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import Foundation

// MARK: - Bridge Info
struct BridgeInfo: Codable, Identifiable, Equatable {
    let id: String
    let internalipaddress: String
    let port: Int
    let serviceName: String?
    
    var displayAddress: String {
        return "\(internalipaddress):\(port)"
    }
    
    var shortId: String {
        return String(id.prefix(8)) + "..."
    }
    
    var displayName: String {
        return serviceName ?? shortId
    }
}

// MARK: - Bridge Connection Info
struct BridgeConnectionInfo: Codable, Equatable {
    let bridge: BridgeInfo
    let username: String
    let clientkey: String?
    let connectedDate: Date

    init(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        self.bridge = bridge
        self.username = registrationResponse.username
        self.clientkey = registrationResponse.clientkey
        self.connectedDate = Date()
    }
}

// MARK: - Bridge Registration Response
struct BridgeRegistrationResponse: Codable {
    let username: String
    let clientkey: String?
}

// MARK: - Hue Bridge Error
struct HueBridgeError: Codable {
    let type: Int
    let address: String
    let description: String
}

struct HueBridgeErrorResponse: Codable {
    let error: HueBridgeError
}

// MARK: - Bridge Registration Error
enum BridgeRegistrationError: Error, LocalizedError {
    case linkButtonNotPressed(String)
    case bridgeError(String)
    case networkError(Error)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .linkButtonNotPressed(let description):
            return description
        case .bridgeError(let description):
            return description
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Scene Models
struct HueScene: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let idV1: String?
    let type: String
    let metadata: SceneMetadata
    let group: ResourceReference
    let actions: [SceneAction]?
    let palette: ScenePalette?
    let speed: Double?
    let autoDynamic: Bool?
    let status: SceneStatus?

    enum CodingKeys: String, CodingKey {
        case id, type, metadata, group, actions, palette, speed, status
        case idV1 = "id_v1"
        case autoDynamic = "auto_dynamic"
    }

    // Custom Equatable implementation
    static func == (lhs: HueScene, rhs: HueScene) -> Bool {
        lhs.id == rhs.id &&
        lhs.metadata.name == rhs.metadata.name &&
        lhs.status?.active == rhs.status?.active
    }

    // Custom Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SceneMetadata: Codable, Equatable, Hashable {
    let name: String
    let image: ResourceReference?
}

struct ResourceReference: Codable, Equatable, Hashable {
    let rid: String
    let rtype: String
}

struct SceneAction: Codable, Equatable, Hashable {
    let target: ResourceReference
    let action: LightAction
}

struct LightAction: Codable, Equatable, Hashable {
    let on: OnState?
    let dimming: DimmingState?
    let color: ColorState?
    let colorTemperature: ColorTemperatureState?

    enum CodingKeys: String, CodingKey {
        case on, dimming, color
        case colorTemperature = "color_temperature"
    }

    struct OnState: Codable, Equatable, Hashable {
        let on: Bool
    }

    struct DimmingState: Codable, Equatable, Hashable {
        let brightness: Double
    }

    struct ColorTemperatureState: Codable, Equatable, Hashable {
        let mirek: Int?
    }
}

struct ColorState: Codable, Equatable, Hashable {
    let xy: XYColor?

    struct XYColor: Codable, Equatable, Hashable {
        let x: Double
        let y: Double
    }
}

struct ScenePalette: Codable, Equatable, Hashable {
    let color: [PaletteColor]?
    let dimming: [PaletteDimming]?
    let colorTemperature: [PaletteColorTemp]?

    enum CodingKeys: String, CodingKey {
        case color, dimming
        case colorTemperature = "color_temperature"
    }
}

struct PaletteColor: Codable, Equatable, Hashable {
    let color: ColorState?
    let dimming: LightAction.DimmingState?
}

struct PaletteDimming: Codable, Equatable, Hashable {
    let brightness: Double
}

struct PaletteColorTemp: Codable, Equatable, Hashable {
    let colorTemperature: LightAction.ColorTemperatureState?
    let dimming: LightAction.DimmingState?

    enum CodingKeys: String, CodingKey {
        case dimming
        case colorTemperature = "color_temperature"
    }
}

struct SceneStatus: Codable, Equatable, Hashable {
    let active: String  // "inactive", "active", "static_no_sf", etc.
}