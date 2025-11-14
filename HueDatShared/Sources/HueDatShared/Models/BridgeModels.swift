//
//  BridgeModels.swift
//  HueDatShared
//
//  Created by David Tanquary on 10/29/25.
//

import Foundation

// MARK: - Bridge Info
public struct BridgeInfo: Codable, Identifiable, Equatable {
    public let id: String
    public let internalipaddress: String
    public let port: Int
    public let serviceName: String?

    public var displayAddress: String {
        /*return "\(internalipaddress):\(port)"*/
        return "\(internalipaddress)"
    }

    public var shortId: String {
        return String(id.prefix(8)) + "..."
    }

    public var displayName: String {
        return serviceName ?? shortId
    }

    public init(id: String, internalipaddress: String, port: Int, serviceName: String?) {
        self.id = id
        self.internalipaddress = internalipaddress
        self.port = port
        self.serviceName = serviceName
    }
}

// MARK: - Bridge Connection Info
public struct BridgeConnectionInfo: Codable, Equatable {
    public let bridge: BridgeInfo
    public let username: String
    public let clientkey: String?
    public let connectedDate: Date

    public init(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        self.bridge = bridge
        self.username = registrationResponse.username
        self.clientkey = registrationResponse.clientkey
        self.connectedDate = Date()
    }
}

// MARK: - Bridge Registration Response
public struct BridgeRegistrationResponse: Codable {
    public let username: String
    public let clientkey: String?

    public init(username: String, clientkey: String?) {
        self.username = username
        self.clientkey = clientkey
    }
}

// MARK: - Hue Bridge Error
public struct HueBridgeError: Codable {
    public let type: Int
    public let address: String
    public let description: String
}

public struct HueBridgeErrorResponse: Codable {
    public let error: HueBridgeError
}

// MARK: - Bridge Registration Error
public enum BridgeRegistrationError: Error, LocalizedError {
    case linkButtonNotPressed(String)
    case bridgeError(String)
    case networkError(Error)
    case unknownError

    public var errorDescription: String? {
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
public struct HueScene: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let idV1: String?
    public let type: String
    public let metadata: SceneMetadata
    public let group: ResourceReference
    public let actions: [SceneAction]?
    public let palette: ScenePalette?
    public let speed: Double?
    public let autoDynamic: Bool?
    public let status: SceneStatus?

    public enum CodingKeys: String, CodingKey {
        case id, type, metadata, group, actions, palette, speed, status
        case idV1 = "id_v1"
        case autoDynamic = "auto_dynamic"
    }

    // Custom Equatable implementation
    public static func == (lhs: HueScene, rhs: HueScene) -> Bool {
        lhs.id == rhs.id &&
        lhs.metadata.name == rhs.metadata.name &&
        lhs.status?.active == rhs.status?.active
    }

    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct SceneMetadata: Codable, Equatable, Hashable {
    public let name: String
    public let image: ResourceReference?
}

public struct ResourceReference: Codable, Equatable, Hashable {
    public let rid: String
    public let rtype: String
}

public struct SceneAction: Codable, Equatable, Hashable {
    public let target: ResourceReference
    public let action: LightAction
}

public struct LightAction: Codable, Equatable, Hashable {
    public let on: OnState?
    public let dimming: DimmingState?
    public let color: ColorState?
    public let colorTemperature: ColorTemperatureState?

    public enum CodingKeys: String, CodingKey {
        case on, dimming, color
        case colorTemperature = "color_temperature"
    }

    public struct OnState: Codable, Equatable, Hashable {
        public let on: Bool
    }

    public struct DimmingState: Codable, Equatable, Hashable {
        public let brightness: Double
    }

    public struct ColorTemperatureState: Codable, Equatable, Hashable {
        public let mirek: Int?
    }
}

public struct ColorState: Codable, Equatable, Hashable {
    public let xy: XYColor?

    public struct XYColor: Codable, Equatable, Hashable {
        public let x: Double
        public let y: Double
    }
}

public struct ScenePalette: Codable, Equatable, Hashable {
    public let color: [PaletteColor]?
    public let dimming: [PaletteDimming]?
    public let colorTemperature: [PaletteColorTemp]?

    public enum CodingKeys: String, CodingKey {
        case color, dimming
        case colorTemperature = "color_temperature"
    }
}

public struct PaletteColor: Codable, Equatable, Hashable {
    public let color: ColorState?
    public let dimming: LightAction.DimmingState?
}

public struct PaletteDimming: Codable, Equatable, Hashable {
    public let brightness: Double
}

public struct PaletteColorTemp: Codable, Equatable, Hashable {
    public let colorTemperature: LightAction.ColorTemperatureState?
    public let dimming: LightAction.DimmingState?

    public enum CodingKeys: String, CodingKey {
        case dimming
        case colorTemperature = "color_temperature"
    }
}

public struct SceneStatus: Codable, Equatable, Hashable {
    public let active: String  // "inactive", "active", "static_no_sf", etc.
}
