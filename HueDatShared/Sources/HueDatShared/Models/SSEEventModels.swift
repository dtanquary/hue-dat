//
//  SSEEventModels.swift
//  HueDatShared
//
//  Server-Sent Events (SSE) data models for Hue API v2 real-time updates
//

import Foundation

// MARK: - SSE Event Types

/// SSE event type from Hue bridge
public enum SSEEventType: String, Codable, Sendable {
    case update
    case add
    case delete
    case error
}

/// Resource type in SSE event data
public enum SSEResourceType: String, Codable, Sendable {
    case light
    case groupedLight = "grouped_light"
    case room
    case zone
    case scene
    case device
    case motion
    case button
    case entertainment
    case behavior_script
    case geofence_client
    case geolocation
    case homekit
    case matter
    case smart_scene
    case temperature
    case zigbee_connectivity
}

// MARK: - SSE Event Structures

/// Top-level SSE event wrapper from Hue API v2
public struct SSEEvent: Codable, Sendable {
    public let creationtime: String
    public let data: [SSEEventData]
    public let id: String
    public let type: String  // Usually "update"

    public var eventType: SSEEventType {
        SSEEventType(rawValue: type) ?? .update
    }
}

/// Individual resource update within an SSE event
public struct SSEEventData: Codable, Sendable {
    public let id: String
    public let type: String

    // Grouped light / light state fields
    public let on: OnState?
    public let dimming: DimmingState?
    public let color_temperature: ColorTemperatureState?
    public let color: ColorState?

    // Room/zone metadata fields
    public let metadata: MetadataState?
    public let children: [ChildReference]?
    public let services: [ServiceReference]?

    // Scene fields
    public let status: SceneStatus?
    public let recall: SceneRecall?

    public var resourceType: SSEResourceType? {
        SSEResourceType(rawValue: type)
    }

    // MARK: - Nested Types

    public struct OnState: Codable, Sendable {
        public let on: Bool
    }

    public struct DimmingState: Codable, Sendable {
        public let brightness: Double  // 0.0 to 100.0
    }

    public struct ColorTemperatureState: Codable, Sendable {
        public let mirek: Int?
        public let mirek_valid: Bool?
    }

    public struct ColorState: Codable, Sendable {
        public let xy: XYColor

        public struct XYColor: Codable, Sendable {
            public let x: Double
            public let y: Double
        }
    }

    public struct MetadataState: Codable, Sendable {
        public let name: String?
        public let archetype: String?
    }

    public struct ChildReference: Codable, Sendable {
        public let rid: String
        public let rtype: String
    }

    public struct ServiceReference: Codable, Sendable {
        public let rid: String
        public let rtype: String
    }

    public struct SceneStatus: Codable, Sendable {
        public let active: String?  // "active", "inactive", or "dynamic_palette"
    }

    public struct SceneRecall: Codable, Sendable {
        public let action: String?  // "active", "static", "dynamic_palette"
        public let status: String?
        public let duration: Int?
        public let dimming: DimmingState?
    }
}

// MARK: - Event Processing Helpers

extension SSEEventData {
    /// Check if this event should trigger a UI update
    public var shouldProcessUpdate: Bool {
        guard let resourceType = resourceType else { return false }

        switch resourceType {
        case .groupedLight, .room, .zone, .scene:
            return true
        case .light, .device, .motion, .button:
            return false  // Skip for now, can enable later
        default:
            return false
        }
    }

    /// Extract human-readable description for debugging
    public var debugDescription: String {
        var parts: [String] = [type, id.prefix(8).description]

        if let on = on {
            parts.append("on:\(on.on)")
        }
        if let brightness = dimming?.brightness {
            parts.append("brightness:\(Int(brightness))%")
        }
        if let name = metadata?.name {
            parts.append("name:'\(name)'")
        }
        if let status = status?.active {
            parts.append("status:\(status)")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Array Extension for Batch Processing

extension Array where Element == SSEEvent {
    /// Extract all event data items from multiple events
    public var allEventData: [SSEEventData] {
        flatMap { $0.data }
    }

    /// Filter to only events that should trigger updates
    public var relevantUpdates: [SSEEventData] {
        allEventData.filter { $0.shouldProcessUpdate }
    }

    /// Count events by resource type for debugging
    public var eventCountByType: [SSEResourceType: Int] {
        var counts: [SSEResourceType: Int] = [:]
        for data in allEventData {
            if let type = data.resourceType {
                counts[type, default: 0] += 1
            }
        }
        return counts
    }
}
