//
//  IconForArchetype.swift
//  HueDatShared
//
//  Centralized SF Symbol mapping for Hue room/zone archetypes.
//  Previously duplicated across 6+ view files across all platforms.
//

import Foundation

/// Returns the appropriate SF Symbol name for a Hue room/zone archetype string.
///
/// Usage:
/// ```swift
/// Image(systemName: iconForArchetype(room.metadata.archetype))
/// ```
public func iconForArchetype(_ archetype: String) -> String {
    switch archetype.lowercased() {
    case "living_room": return "sofa"
    case "bedroom": return "bed.double"
    case "kitchen": return "fork.knife"
    case "bathroom": return "shower"
    case "office", "computer": return "desktopcomputer"
    case "dining": return "fork.knife"
    case "garage": return "car"
    case "hallway", "front_door": return "door.left.hand.open"
    case "kids_bedroom", "nursery": return "figure.and.child.holdinghands"
    case "closet", "storage": return "cabinet"
    case "laundry_room": return "washer"
    case "terrace", "balcony": return "sun.max"
    case "garden", "outdoor": return "leaf"
    case "gym", "recreation": return "figure.run"
    case "toilet": return "drop"
    case "other": return "lightbulb"
    default: return "lightbulb"
    }
}
