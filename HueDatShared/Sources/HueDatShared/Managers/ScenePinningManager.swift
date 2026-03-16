//
//  ScenePinningManager.swift
//  HueDatShared
//
//  Extracted from BridgeManager - manages scene pinning (favorites)
//  per bridge and per room/zone group.
//

import Foundation
import Observation
import os

/// Manages pinned (favorite) scenes per bridge and per room/zone.
///
/// Storage layout: `[bridgeId: [groupId: [sceneId]]]`
/// Arrays preserve insertion order for UI display.
@MainActor
@Observable
public class ScenePinningManager {

    // MARK: - State

    /// The full pinning dictionary: bridgeId -> groupId -> ordered scene IDs
    public private(set) var pinnedSceneIds: [String: [String: [String]]] = [:]

    // MARK: - Storage

    @ObservationIgnored private let userDefaults = UserDefaults.standard
    @ObservationIgnored private let pinnedScenesKey = "PinnedScenes"

    // MARK: - Init

    public init() {
        loadPinnedScenesFromStorage()
    }

    // MARK: - Pin / Unpin Operations

    /// Pin a scene to a specific room or zone.
    public func pinScene(sceneId: String, forGroupId groupId: String, bridgeId: String?) {
        guard let bridgeId = bridgeId else {
            AppLogger.pinning.warning("pinScene: No connected bridge - operation skipped")
            return
        }

        if pinnedSceneIds[bridgeId] == nil {
            pinnedSceneIds[bridgeId] = [:]
        }
        if pinnedSceneIds[bridgeId]?[groupId] == nil {
            pinnedSceneIds[bridgeId]?[groupId] = []
        }

        if let scenes = pinnedSceneIds[bridgeId]?[groupId], scenes.contains(sceneId) {
            AppLogger.pinning.debug("pinScene: Scene \(sceneId, privacy: .public) already pinned to group \(groupId, privacy: .public)")
            return
        }

        pinnedSceneIds[bridgeId]?[groupId]?.append(sceneId)
        savePinnedScenesToStorage()
        AppLogger.pinning.info("pinScene: Pinned scene \(sceneId, privacy: .public) to group \(groupId, privacy: .public)")
    }

    /// Unpin a scene from a specific room or zone.
    public func unpinScene(sceneId: String, forGroupId groupId: String, bridgeId: String?) {
        guard let bridgeId = bridgeId else {
            AppLogger.pinning.warning("unpinScene: No connected bridge - operation skipped")
            return
        }

        guard var groupScenes = pinnedSceneIds[bridgeId]?[groupId] else {
            AppLogger.pinning.debug("unpinScene: No pinned scenes for group \(groupId, privacy: .public)")
            return
        }

        groupScenes.removeAll { $0 == sceneId }

        if groupScenes.isEmpty {
            pinnedSceneIds[bridgeId]?[groupId] = nil
        } else {
            pinnedSceneIds[bridgeId]?[groupId] = groupScenes
        }

        savePinnedScenesToStorage()
        AppLogger.pinning.info("unpinScene: Unpinned scene \(sceneId, privacy: .public) from group \(groupId, privacy: .public)")
    }

    /// Toggle pin state for a scene.
    public func toggleScenePin(sceneId: String, forGroupId groupId: String, bridgeId: String?) {
        if isScenePinned(sceneId: sceneId, forGroupId: groupId, bridgeId: bridgeId) {
            unpinScene(sceneId: sceneId, forGroupId: groupId, bridgeId: bridgeId)
        } else {
            pinScene(sceneId: sceneId, forGroupId: groupId, bridgeId: bridgeId)
        }
    }

    // MARK: - Query Methods

    /// Check if a scene is pinned.
    public func isScenePinned(sceneId: String, forGroupId groupId: String, bridgeId: String?) -> Bool {
        guard let bridgeId = bridgeId else { return false }
        return pinnedSceneIds[bridgeId]?[groupId]?.contains(sceneId) ?? false
    }

    /// Return pinned scenes for a group, in pinned order.
    public func getPinnedScenes(forGroupId groupId: String, bridgeId: String?, scenes: [HueScene]) -> [HueScene] {
        guard let bridgeId = bridgeId else { return [] }
        guard let pinnedIds = pinnedSceneIds[bridgeId]?[groupId] else { return [] }

        return pinnedIds.compactMap { sceneId -> HueScene? in
            scenes.first { $0.id == sceneId && $0.group.rid == groupId }
        }
    }

    /// Count of pinned scenes for a group.
    public func getPinnedSceneCount(forGroupId groupId: String, bridgeId: String?) -> Int {
        guard let bridgeId = bridgeId else { return 0 }
        return pinnedSceneIds[bridgeId]?[groupId]?.count ?? 0
    }

    // MARK: - Cleanup

    /// Clear all pinned scenes for a specific group.
    public func clearPinnedScenes(forGroupId groupId: String, bridgeId: String?) {
        guard let bridgeId = bridgeId else {
            AppLogger.pinning.warning("clearPinnedScenes: No connected bridge - operation skipped")
            return
        }
        pinnedSceneIds[bridgeId]?[groupId] = nil
        savePinnedScenesToStorage()
        AppLogger.pinning.info("clearPinnedScenes: Cleared all pinned scenes for group \(groupId, privacy: .public)")
    }

    /// Clear ALL pinned scenes across all bridges.
    public func clearAllPinnedScenes() {
        pinnedSceneIds = [:]
        savePinnedScenesToStorage()
        AppLogger.pinning.info("clearAllPinnedScenes: Cleared all pinned scenes")
    }

    /// Remove pins for a specific bridge (called on disconnect).
    public func clearPinnedScenes(forBridgeId bridgeId: String) {
        pinnedSceneIds[bridgeId] = nil
        savePinnedScenesToStorage()
    }

    /// Validate and clean up stale pinned scenes.
    /// Removes scene IDs that no longer exist in the provided scenes array.
    public func validateAndCleanPinnedScenes(bridgeId: String?, scenes: [HueScene]) {
        guard let bridgeId = bridgeId else { return }
        guard var bridgePins = pinnedSceneIds[bridgeId] else { return }

        var didClean = false

        for (groupId, sceneIds) in bridgePins {
            let groupScenes = scenes.filter { $0.group.rid == groupId }
            let validSceneIds = Set(groupScenes.map { $0.id })
            let validPins = sceneIds.filter { validSceneIds.contains($0) }

            if validPins.count != sceneIds.count {
                let removed = sceneIds.count - validPins.count
                AppLogger.pinning.debug("validateAndCleanPinnedScenes: Cleaned \(removed, privacy: .public) stale pinned scene(s) for group \(groupId, privacy: .public)")

                if validPins.isEmpty {
                    bridgePins[groupId] = nil
                } else {
                    bridgePins[groupId] = validPins
                }
                didClean = true
            }
        }

        if didClean {
            pinnedSceneIds[bridgeId] = bridgePins
            savePinnedScenesToStorage()
        }
    }

    // MARK: - Persistence

    public func loadPinnedScenesFromStorage() {
        guard let data = userDefaults.data(forKey: pinnedScenesKey) else {
            AppLogger.pinning.debug("No pinned scenes found")
            return
        }

        do {
            pinnedSceneIds = try JSONDecoder().decode([String: [String: [String]]].self, from: data)
            let totalPins = pinnedSceneIds.values.flatMap { $0.values }.reduce(0) { $0 + $1.count }
            AppLogger.pinning.info("Loaded \(totalPins, privacy: .public) pinned scenes from storage")
        } catch {
            AppLogger.pinning.error("Failed to load pinned scenes: \(error.localizedDescription, privacy: .public)")
            userDefaults.removeObject(forKey: pinnedScenesKey)
        }
    }

    public func savePinnedScenesToStorage() {
        do {
            let data = try JSONEncoder().encode(pinnedSceneIds)
            userDefaults.set(data, forKey: pinnedScenesKey)
            let totalPins = pinnedSceneIds.values.flatMap { $0.values }.reduce(0) { $0 + $1.count }
            AppLogger.pinning.debug("Saved \(totalPins, privacy: .public) pinned scenes to storage (\(data.count, privacy: .public) bytes)")
        } catch {
            AppLogger.pinning.error("Failed to save pinned scenes to storage: \(error.localizedDescription, privacy: .public)")
        }
    }
}
