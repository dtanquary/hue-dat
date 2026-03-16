//
//  SearchManager.swift
//  HueDatShared
//
//  Fast, in-memory search across rooms, zones, and scenes
//

import Foundation
import Observation
import os

// MARK: - Scene Search Result with Context

/// A scene search result that includes the associated room or zone
public struct SceneSearchResult: Identifiable, Hashable {
    public let scene: HueScene
    public let associatedRoom: HueRoom?
    public let associatedZone: HueZone?

    public var id: String { scene.id }

    /// Display name with context: "Bright - Living Room"
    public var displayName: String {
        if let room = associatedRoom {
            return "\(scene.metadata.name) - \(room.metadata.name)"
        } else if let zone = associatedZone {
            return "\(scene.metadata.name) - \(zone.metadata.name)"
        }
        return scene.metadata.name
    }

    /// Context description: "in Living Room"
    public var contextDescription: String? {
        if let room = associatedRoom {
            return "in \(room.metadata.name)"
        } else if let zone = associatedZone {
            return "in \(zone.metadata.name)"
        }
        return nil
    }

    public init(scene: HueScene, associatedRoom: HueRoom?, associatedZone: HueZone?) {
        self.scene = scene
        self.associatedRoom = associatedRoom
        self.associatedZone = associatedZone
    }
}

// MARK: - Search Results

/// Container for all search results
public struct SearchResults {
    public let rooms: [HueRoom]
    public let zones: [HueZone]
    public let scenes: [SceneSearchResult]

    /// True if no results found
    public var isEmpty: Bool {
        rooms.isEmpty && zones.isEmpty && scenes.isEmpty
    }

    /// Total number of matches across all types
    public var totalCount: Int {
        rooms.count + zones.count + scenes.count
    }

    public init(rooms: [HueRoom], zones: [HueZone], scenes: [SceneSearchResult]) {
        self.rooms = rooms
        self.zones = zones
        self.scenes = scenes
    }
}

// MARK: - Search Manager

/// Fast, in-memory search manager for rooms, zones, and scenes
///
/// Usage:
/// ```swift
/// let searchManager = SearchManager(bridgeManager: bridgeManager)
/// let results = searchManager.search("living")
/// print("Found \(results.totalCount) matches")
/// ```
@MainActor
@Observable
public class SearchManager {

    // MARK: - Properties

    /// Weak reference to BridgeManager to prevent retain cycles
    @ObservationIgnored private weak var bridgeManager: BridgeManager?

    // MARK: - Initialization

    public init(bridgeManager: BridgeManager) {
        self.bridgeManager = bridgeManager
    }

    // MARK: - Public Search Methods

    /// Search across all types (rooms, zones, scenes)
    /// - Parameter query: Search string (empty returns no results)
    /// - Returns: Search results container
    public func search(_ query: String) -> SearchResults {
        AppLogger.search.debug("Searching for '\(query, privacy: .public)'")

        let rooms = searchRooms(query)
        let zones = searchZones(query)
        let scenes = searchScenes(query)

        let results = SearchResults(rooms: rooms, zones: zones, scenes: scenes)

        AppLogger.search.debug("Found \(results.totalCount, privacy: .public) total matches (rooms: \(rooms.count, privacy: .public), zones: \(zones.count, privacy: .public), scenes: \(scenes.count, privacy: .public))")

        return results
    }

    /// Search rooms only
    /// - Parameter query: Search string (empty returns no results)
    /// - Returns: Array of matching rooms
    public func searchRooms(_ query: String) -> [HueRoom] {
        guard let bridgeManager = bridgeManager else {
            AppLogger.search.warning("BridgeManager not available")
            return []
        }

        guard !query.isEmpty else {
            return []
        }

        return bridgeManager.rooms.filter { room in
            matches(room.metadata.name, query: query)
        }
    }

    /// Search zones only
    /// - Parameter query: Search string (empty returns no results)
    /// - Returns: Array of matching zones
    public func searchZones(_ query: String) -> [HueZone] {
        guard let bridgeManager = bridgeManager else {
            AppLogger.search.warning("BridgeManager not available")
            return []
        }

        guard !query.isEmpty else {
            return []
        }

        return bridgeManager.zones.filter { zone in
            matches(zone.metadata.name, query: query)
        }
    }

    /// Search scenes only (with room/zone context)
    /// - Parameter query: Search string (empty returns no results)
    /// - Returns: Array of matching scenes with context
    public func searchScenes(_ query: String) -> [SceneSearchResult] {
        guard let bridgeManager = bridgeManager else {
            AppLogger.search.warning("BridgeManager not available")
            return []
        }

        guard !query.isEmpty else {
            return []
        }

        var results: [SceneSearchResult] = []

        for scene in bridgeManager.scenes {
            // Only include if name matches
            guard matches(scene.metadata.name, query: query) else { continue }

            // Find associated room or zone
            let groupId = scene.group.rid
            let groupType = scene.group.rtype

            if groupType == "room" {
                if let room = bridgeManager.rooms.first(where: { $0.id == groupId }) {
                    results.append(SceneSearchResult(
                        scene: scene,
                        associatedRoom: room,
                        associatedZone: nil
                    ))
                }
                // Skip scenes without room context
            } else if groupType == "zone" {
                if let zone = bridgeManager.zones.first(where: { $0.id == groupId }) {
                    results.append(SceneSearchResult(
                        scene: scene,
                        associatedRoom: nil,
                        associatedZone: zone
                    ))
                }
                // Skip scenes without zone context
            }
        }

        return results
    }

    // MARK: - Utility Methods

    /// Check if query has any matches
    /// - Parameter query: Search string
    /// - Returns: True if any matches found
    public func hasMatches(for query: String) -> Bool {
        guard !query.isEmpty else { return false }

        let rooms = searchRooms(query)
        if !rooms.isEmpty { return true }

        let zones = searchZones(query)
        if !zones.isEmpty { return true }

        let scenes = searchScenes(query)
        return !scenes.isEmpty
    }

    /// Get total match count without full results
    /// - Parameter query: Search string
    /// - Returns: Total number of matches
    public func matchCount(for query: String) -> Int {
        let results = search(query)
        return results.totalCount
    }

    // MARK: - Private Helper Methods

    /// Case-insensitive substring matching
    /// - Parameters:
    ///   - text: Text to search in
    ///   - query: Search query
    /// - Returns: True if text contains query (case-insensitive)
    private func matches(_ text: String, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(query)
    }
}
