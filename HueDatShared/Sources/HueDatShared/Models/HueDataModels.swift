//
//  HueDataModels.swift
//  HueDatShared
//
//  Hue API v2 data models for rooms, zones, grouped lights, and individual lights
//

import Foundation

// MARK: - API Error Models

/// Hue API v2 error structure
public struct HueAPIV2Error: Codable, Sendable {
    public let description: String
}

// MARK: - Room Models

/// Hue room with metadata, children, services, and grouped lights
public struct HueRoom: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let type: String
    public var metadata: RoomMetadata
    public var children: [HueRoomChild]?
    public var services: [HueRoomService]?
    public var groupedLights: [HueGroupedLight]?

    public struct RoomMetadata: Codable, Equatable, Hashable, Sendable {
        public let name: String
        public let archetype: String
    }

    /// Child references in Hue API v2 rooms
    /// NOTE: Children with rtype="device" contain device IDs, NOT light IDs.
    /// To get light data: 1) Query /clip/v2/resource/device/{rid} to get device
    /// 2) Find service with rtype="light" in device.services to get actual light ID
    /// 3) Query /clip/v2/resource/light/{lightId} with the light ID from step 2
    public struct HueRoomChild: Codable, Equatable, Hashable, Sendable {
        public let rid: String   // Resource ID (device ID when rtype="device")
        public let rtype: String // Resource type (e.g., "device", "motion", etc.)
    }

    public struct HueRoomService: Codable, Equatable, Hashable, Sendable {
        public let rid: String
        public let rtype: String
    }

    // Custom Equatable implementation for efficient comparison
    public static func == (lhs: HueRoom, rhs: HueRoom) -> Bool {
        lhs.id == rhs.id &&
        lhs.metadata == rhs.metadata &&
        lhs.groupedLights == rhs.groupedLights
    }

    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Zone Models

/// Hue zone with metadata, children, services, and grouped lights
public struct HueZone: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let type: String
    public var metadata: ZoneMetadata
    public var children: [HueZoneChild]?
    public var services: [HueZoneService]?
    public var groupedLights: [HueGroupedLight]?

    public struct ZoneMetadata: Codable, Equatable, Hashable, Sendable {
        public let name: String
        public let archetype: String
    }

    /// Child references in Hue API v2 zones
    /// NOTE: Children with rtype="device" contain device IDs, NOT light IDs.
    /// To get light data: 1) Query /clip/v2/resource/device/{rid} to get device
    /// 2) Find service with rtype="light" in device.services to get actual light ID
    /// 3) Query /clip/v2/resource/light/{lightId} with the light ID from step 2
    public struct HueZoneChild: Codable, Equatable, Hashable, Sendable {
        public let rid: String   // Resource ID (device ID when rtype="device")
        public let rtype: String // Resource type (e.g., "device", "motion", etc.)
    }

    public struct HueZoneService: Codable, Equatable, Hashable, Sendable {
        public let rid: String
        public let rtype: String
    }

    // Custom Equatable implementation for efficient comparison
    public static func == (lhs: HueZone, rhs: HueZone) -> Bool {
        lhs.id == rhs.id &&
        lhs.metadata == rhs.metadata &&
        lhs.groupedLights == rhs.groupedLights
    }

    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Grouped Light Models

/// Aggregated light status for a room or zone
public struct HueGroupedLight: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let on: GroupedLightOn?
    public let dimming: GroupedLightDimming?
    public let color_temperature: GroupedLightColorTemperature?
    public let color: GroupedLightColor?

    public struct GroupedLightOn: Codable, Equatable, Hashable, Sendable {
        public let on: Bool
    }

    public struct GroupedLightDimming: Codable, Equatable, Hashable, Sendable {
        public let brightness: Double
    }

    public struct GroupedLightColorTemperature: Codable, Equatable, Hashable, Sendable {
        public let mirek: Int?
        public let mirek_valid: Bool?
        public let mirek_schema: GroupedLightColorTemperatureSchema?

        public struct GroupedLightColorTemperatureSchema: Codable, Equatable, Hashable, Sendable {
            public let mirek_minimum: Int
            public let mirek_maximum: Int
        }
    }

    public struct GroupedLightColor: Codable, Equatable, Hashable, Sendable {
        public let xy: GroupedLightColorXY?
        public let gamut: GroupedLightColorGamut?
        public let gamut_type: String?

        public struct GroupedLightColorXY: Codable, Equatable, Hashable, Sendable {
            public let x: Double
            public let y: Double
        }

        public struct GroupedLightColorGamut: Codable, Equatable, Hashable, Sendable {
            public let red: GroupedLightColorXY
            public let green: GroupedLightColorXY
            public let blue: GroupedLightColorXY
        }
    }

    // Custom Equatable implementation
    public static func == (lhs: HueGroupedLight, rhs: HueGroupedLight) -> Bool {
        lhs.id == rhs.id &&
        lhs.on?.on == rhs.on?.on &&
        lhs.dimming?.brightness == rhs.dimming?.brightness &&
        lhs.color_temperature?.mirek == rhs.color_temperature?.mirek &&
        lhs.color?.xy?.x == rhs.color?.xy?.x &&
        lhs.color?.xy?.y == rhs.color?.xy?.y
    }

    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Individual Light Models

/// Individual light with full status information
public struct HueLight: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let metadata: LightMetadata?
    public let on: LightOn?
    public let dimming: LightDimming?
    public let color_temperature: LightColorTemperature?
    public let color: LightColor?

    public struct LightMetadata: Codable, Equatable, Hashable, Sendable {
        public let name: String
        public let archetype: String?
    }

    public struct LightOn: Codable, Equatable, Hashable, Sendable {
        public let on: Bool
    }

    public struct LightDimming: Codable, Equatable, Hashable, Sendable {
        public let brightness: Double
    }

    public struct LightColorTemperature: Codable, Equatable, Hashable, Sendable {
        public let mirek: Int?
        public let mirek_valid: Bool?
    }

    public struct LightColor: Codable, Equatable, Hashable, Sendable {
        public let xy: LightColorXY?
        public let gamut: LightColorGamut?
        public let gamut_type: String?

        public struct LightColorXY: Codable, Equatable, Hashable, Sendable {
            public let x: Double
            public let y: Double
        }

        public struct LightColorGamut: Codable, Equatable, Hashable, Sendable {
            public let red: LightColorXY
            public let green: LightColorXY
            public let blue: LightColorXY
        }
    }

    // Custom Equatable implementation
    public static func == (lhs: HueLight, rhs: HueLight) -> Bool {
        lhs.id == rhs.id &&
        lhs.on?.on == rhs.on?.on &&
        lhs.dimming?.brightness == rhs.dimming?.brightness &&
        lhs.color_temperature?.mirek == rhs.color_temperature?.mirek &&
        lhs.color?.xy?.x == rhs.color?.xy?.x &&
        lhs.color?.xy?.y == rhs.color?.xy?.y
    }

    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Device Models

/// Hue device information (for device → light resolution)
public struct HueDevice: Codable, Sendable {
    public let id: String
    public let type: String
    public let services: [HueDeviceService]?
    public let metadata: HueDeviceMetadata?

    public struct HueDeviceService: Codable, Sendable {
        public let rid: String   // Resource ID (the light ID if rtype is "light")
        public let rtype: String // Resource type (e.g., "light", "zigbee_connectivity", etc.)
    }

    public struct HueDeviceMetadata: Codable, Sendable {
        public let name: String?
        public let archetype: String?
    }
}

// MARK: - API Response Wrappers

/// Response wrapper for room queries
public struct HueRoomsResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueRoom]
}

/// Response wrapper for room detail queries
public struct HueRoomDetailResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueRoomDetail]
}

/// Detailed room information from individual room query
public struct HueRoomDetail: Codable {
    public let id: String
    public let type: String
    public let metadata: HueRoom.RoomMetadata
    public let children: [HueRoom.HueRoomChild]?
    public let services: [HueRoom.HueRoomService]?
}

/// Response wrapper for zone queries
public struct HueZonesResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueZone]
}

/// Response wrapper for zone detail queries
public struct HueZoneDetailResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueZoneDetail]
}

/// Detailed zone information from individual zone query
public struct HueZoneDetail: Codable {
    public let id: String
    public let type: String
    public let metadata: HueZone.ZoneMetadata
    public let children: [HueZone.HueZoneChild]?
    public let services: [HueZone.HueZoneService]?
}

/// Response wrapper for grouped light queries
public struct HueGroupedLightsResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueGroupedLight]
}

/// Response wrapper for grouped light detail queries
public struct HueGroupedLightResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueGroupedLight]
}

/// Response wrapper for light queries
public struct HueLightsResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueLight]
}

/// Response wrapper for light detail queries
public struct HueLightResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueLight]
}

/// Response wrapper for scene queries
public struct HueScenesResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueScene]
}

/// Response wrapper for device queries
public struct HueDeviceResponse: Codable {
    public let errors: [HueAPIV2Error]
    public let data: [HueDevice]
}
