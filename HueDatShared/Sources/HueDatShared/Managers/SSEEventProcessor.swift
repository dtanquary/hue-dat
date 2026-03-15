//
//  SSEEventProcessor.swift
//  HueDatShared
//
//  Extracted from BridgeManager - handles SSE event subscription,
//  processing, and auto-reconnection logic.
//

import Foundation
import Combine

/// Processes SSE events from the Hue bridge and updates BridgeManager state.
///
/// Holds the Combine subscriptions for the event stream and stream-state,
/// manages the reconnection back-off, and dispatches updates to the
/// owning BridgeManager via a weak reference.
@MainActor
public class SSEEventProcessor {

    // MARK: - Properties

    private weak var bridgeManager: BridgeManager?

    private var eventSubscription: AnyCancellable?
    private var streamStateSubscription: AnyCancellable?
    private let maxReconnectAttempts = 5

    /// Cached map: grouped_light ID -> room ID for fast SSE lookup
    internal var groupedLightToRoomMap: [String: String] = [:]

    /// Cached map: grouped_light ID -> zone ID for fast SSE lookup
    internal var groupedLightToZoneMap: [String: String] = [:]

    // MARK: - Init

    public init(bridgeManager: BridgeManager) {
        self.bridgeManager = bridgeManager
    }

    // MARK: - Map Rebuilding

    /// Rebuild a grouped-light-to-group-ID map from a collection of GroupedLightContainers
    private func rebuildGroupedLightMap<T: GroupedLightContainer>(from groups: [T]) -> [String: String] {
        var map: [String: String] = [:]
        for group in groups {
            if let services = group.services,
               let groupedLightService = services.first(where: { $0.rtype == "grouped_light" }) {
                map[groupedLightService.rid] = group.id
            }
        }
        return map
    }

    /// Rebuild the room map from the current rooms in BridgeManager.
    public func rebuildGroupedLightToRoomMap() {
        guard let bm = bridgeManager else { return }
        groupedLightToRoomMap = rebuildGroupedLightMap(from: bm.rooms)
    }

    /// Rebuild the zone map from the current zones in BridgeManager.
    public func rebuildGroupedLightToZoneMap() {
        guard let bm = bridgeManager else { return }
        groupedLightToZoneMap = rebuildGroupedLightMap(from: bm.zones)
    }

    // MARK: - SSE Lifecycle

    /// Start listening to SSE events from HueAPIService.
    public func startListeningToSSEEvents() {
        guard let bm = bridgeManager else { return }

        if bm.isDemoMode {
            print("startListeningToSSEEvents: Demo mode - skipping SSE")
            return
        }

        // Prevent duplicate subscriptions
        if eventSubscription != nil && streamStateSubscription != nil {
            print("SSE event listeners already running - skipping duplicate start")
            return
        }

        print("Starting SSE event listener")

        // Cancel any existing subscriptions first to prevent memory leaks
        eventSubscription?.cancel()
        streamStateSubscription?.cancel()

        Task { [weak self] in
            guard let self = self else { return }
            let service = HueAPIService.shared

            await MainActor.run { [weak self] in
                guard let self = self, let bm = self.bridgeManager else { return }

                self.eventSubscription = service.eventPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] events in
                        guard let self = self else { return }
                        Task {
                            await self.processSSEEvents(events)
                        }
                    }

                self.streamStateSubscription = service.streamStateSubject
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] state in
                        guard let self = self, let bm = self.bridgeManager else { return }

                        bm.isSSEConnected = (state == .connected)

                        if case .disconnected = state, bm.reconnectAttempts < self.maxReconnectAttempts {
                            Task.detached { [weak self] in
                                guard let self = self else { return }
                                await self.handleReconnection()
                            }
                        }
                    }
            }
        }
    }

    /// Stop listening to SSE events.
    public func stopListeningToSSEEvents() {
        print("Stopping SSE event listener")
        eventSubscription?.cancel()
        streamStateSubscription?.cancel()
        eventSubscription = nil
        streamStateSubscription = nil

        if let bm = bridgeManager {
            bm.isSSEConnected = false
            bm.reconnectAttempts = 0
        }
    }

    /// Manually reconnect SSE stream (for user-initiated reconnection).
    public func reconnectSSE() async {
        guard let bm = bridgeManager else { return }

        guard bm.isConnected else {
            print("Cannot reconnect SSE - no bridge connected")
            return
        }

        if bm.isSSEConnected {
            print("SSE already connected - skipping reconnection")
            return
        }

        print("Manually reconnecting SSE stream...")

        stopListeningToSSEEvents()
        bm.reconnectAttempts = 0
        startListeningToSSEEvents()

        do {
            try await HueAPIService.shared.startEventStream()
            print("SSE stream reconnected successfully")
        } catch {
            print("Failed to reconnect SSE stream: \(error.localizedDescription)")
        }
    }

    // MARK: - Event Processing

    /// Process incoming SSE events and update local state.
    private func processSSEEvents(_ events: [SSEEvent]) async {
        let relevantUpdates = events.relevantUpdates

        guard !relevantUpdates.isEmpty else { return }

        print("Processing \(relevantUpdates.count) relevant event(s)")

        for eventData in relevantUpdates {
            switch eventData.resourceType {
            case .groupedLight:
                await handleGroupedLightUpdate(eventData)
            case .room:
                await handleRoomUpdate(eventData)
            case .zone:
                await handleZoneUpdate(eventData)
            case .scene:
                await handleSceneUpdate(eventData)
            default:
                break
            }
        }
    }

    /// Handle grouped_light update event.
    private func handleGroupedLightUpdate(_ data: SSEEventData) async {
        guard let bm = bridgeManager else { return }
        print("Grouped light update: \(data.debugDescription)")

        let groupedLightId = data.id

        if let roomId = groupedLightToRoomMap[groupedLightId] {
            let on = data.on?.on
            let brightness = data.dimming?.brightness
            await MainActor.run {
                bm.updateLocalRoomState(roomId: roomId, on: on, brightness: brightness)
            }
            print("  Updated room \(roomId)")
        }

        if let zoneId = groupedLightToZoneMap[groupedLightId] {
            let on = data.on?.on
            let brightness = data.dimming?.brightness
            await MainActor.run {
                bm.updateLocalZoneState(zoneId: zoneId, on: on, brightness: brightness)
            }
            print("  Updated zone \(zoneId)")
        }
    }

    /// Handle metadata update event for any GroupedLightContainer (room or zone).
    private func handleGroupMetadataUpdate<T: GroupedLightContainer>(
        _ data: SSEEventData,
        in collection: inout [T],
        label: String
    ) {
        let groupId = data.id

        if let metadata = data.metadata, let name = metadata.name {
            if let index = collection.firstIndex(where: { $0.id == groupId }) {
                var updatedItem = collection[index]
                let archetype = metadata.archetype ?? updatedItem.metadata.archetype
                updatedItem.metadata = GroupMetadata(name: name, archetype: archetype)
                collection[index] = updatedItem
                print("  Updated \(label) '\(name)' metadata")
            }
        }
    }

    /// Handle room metadata update event.
    private func handleRoomUpdate(_ data: SSEEventData) async {
        guard let bm = bridgeManager else { return }
        print("Room update: \(data.debugDescription)")
        await MainActor.run {
            self.handleGroupMetadataUpdate(data, in: &bm.rooms, label: "room")
        }
    }

    /// Handle zone metadata update event.
    private func handleZoneUpdate(_ data: SSEEventData) async {
        guard let bm = bridgeManager else { return }
        print("Zone update: \(data.debugDescription)")
        await MainActor.run {
            self.handleGroupMetadataUpdate(data, in: &bm.zones, label: "zone")
        }
    }

    /// Handle scene status update event.
    private func handleSceneUpdate(_ data: SSEEventData) async {
        print("Scene update: \(data.debugDescription)")
        if let status = data.status?.active {
            print("  Scene \(data.id.prefix(8)) is now: \(status)")
        }
    }

    // MARK: - Reconnection

    /// Handle auto-reconnection with exponential backoff.
    /// Called from a detached Task to prevent blocking MainActor.
    private func handleReconnection() async {
        let shouldSkip = await MainActor.run { [weak self] () -> Bool in
            guard let self = self, let bm = self.bridgeManager else { return true }
            return bm.isDemoMode || bm.connectedBridge == nil
        }

        if shouldSkip {
            print("Skipping SSE reconnection - no active bridge connection")
            return
        }

        let (currentAttempt, delay) = await MainActor.run { [weak self] () -> (Int, Double) in
            guard let self = self, let bm = self.bridgeManager else { return (0, 1.0) }
            bm.reconnectAttempts += 1
            let delay = min(pow(2.0, Double(bm.reconnectAttempts - 1)), 32.0)
            return (bm.reconnectAttempts, delay)
        }

        print("SSE disconnected. Reconnecting in \(Int(delay))s (attempt \(currentAttempt)/\(maxReconnectAttempts))")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let bridgeStillConnected = await MainActor.run { [weak self] () -> Bool in
            guard let self = self, let bm = self.bridgeManager else { return false }
            return bm.connectedBridge != nil
        }

        guard bridgeStillConnected else {
            print("Bridge disconnected during reconnection delay - aborting")
            return
        }

        do {
            try await HueAPIService.shared.startEventStream()
            print("SSE stream reconnected")
            await MainActor.run { [weak self] in
                self?.bridgeManager?.reconnectAttempts = 0
            }
        } catch {
            print("Failed to reconnect SSE stream: \(error)")
        }
    }
}
