//
//  SSEEventModels.swift
//  hue dat Watch App
//
//  Server-Sent Events (SSE) data models for Hue API v2 real-time updates
//

import Foundation

// MARK: - SSE Event Types

/// SSE event type from Hue bridge
enum SSEEventType: String, Codable, Sendable {
    case update
    case add
    case delete
    case error
}

/// Resource type in SSE event data
enum SSEResourceType: String, Codable, Sendable {
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
struct SSEEvent: Codable, Sendable {
    let creationtime: String
    let data: [SSEEventData]
    let id: String
    let type: String  // Usually "update"

    var eventType: SSEEventType {
        SSEEventType(rawValue: type) ?? .update
    }
}

/// Individual resource update within an SSE event
struct SSEEventData: Codable, Sendable {
    let id: String
    let type: String

    // Grouped light / light state fields
    let on: OnState?
    let dimming: DimmingState?
    let color_temperature: ColorTemperatureState?
    let color: ColorState?

    // Room/zone metadata fields
    let metadata: MetadataState?
    let children: [ChildReference]?
    let services: [ServiceReference]?

    // Scene fields
    let status: SceneStatus?
    let recall: SceneRecall?

    var resourceType: SSEResourceType? {
        SSEResourceType(rawValue: type)
    }

    // MARK: - Nested Types

    struct OnState: Codable, Sendable {
        let on: Bool
    }

    struct DimmingState: Codable, Sendable {
        let brightness: Double  // 0.0 to 100.0
    }

    struct ColorTemperatureState: Codable, Sendable {
        let mirek: Int?
        let mirek_valid: Bool?
    }

    struct ColorState: Codable, Sendable {
        let xy: XYColor

        struct XYColor: Codable, Sendable {
            let x: Double
            let y: Double
        }
    }

    struct MetadataState: Codable, Sendable {
        let name: String?
        let archetype: String?
    }

    struct ChildReference: Codable, Sendable {
        let rid: String
        let rtype: String
    }

    struct ServiceReference: Codable, Sendable {
        let rid: String
        let rtype: String
    }

    struct SceneStatus: Codable, Sendable {
        let active: String?  // "active", "inactive", or "dynamic_palette"
    }

    struct SceneRecall: Codable, Sendable {
        let action: String?  // "active", "static", "dynamic_palette"
        let status: String?
        let duration: Int?
        let dimming: DimmingState?
    }
}

// MARK: - Event Processing Helpers

extension SSEEventData {
    /// Check if this event should trigger a UI update
    var shouldProcessUpdate: Bool {
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
    var debugDescription: String {
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
    var allEventData: [SSEEventData] {
        flatMap { $0.data }
    }

    /// Filter to only events that should trigger updates
    var relevantUpdates: [SSEEventData] {
        allEventData.filter { $0.shouldProcessUpdate }
    }

    /// Count events by resource type for debugging
    var eventCountByType: [SSEResourceType: Int] {
        var counts: [SSEResourceType: Int] = [:]
        for data in allEventData {
            if let type = data.resourceType {
                counts[type, default: 0] += 1
            }
        }
        return counts
    }
}
