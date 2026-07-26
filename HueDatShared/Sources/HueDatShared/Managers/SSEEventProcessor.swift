//
//  SSEEventProcessor.swift
//  HueDatShared
//
//  Extracted from BridgeManager - handles SSE event subscription,
//  processing, and auto-reconnection logic.
//

import Foundation
import Combine
import os

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

    /// Pending backoff-counter reset; only fires after the connection proves stable.
    private var backoffResetTask: Task<Void, Never>?

    /// Single-flight guard: at most one reconnection may be pending at a time.
    /// Multiple seeders exist (auto-reconnect, wake handler, refreshAllData's
    /// post-refresh check) and stacked reconnections cancel each other's streams.
    private var isReconnectScheduled = false

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
            AppLogger.sse.debug("startListeningToSSEEvents: Demo mode - skipping SSE")
            return
        }

        // Prevent duplicate subscriptions
        if eventSubscription != nil && streamStateSubscription != nil {
            AppLogger.sse.warning("SSE event listeners already running - skipping duplicate start")
            return
        }

        AppLogger.sse.debug("Starting SSE event listener")

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

                        // A connection clears the backoff counter only after it proves
                        // stable for 10s, regardless of which code path got us here
                        // (auto-reconnect, wake-from-sleep restart, manual retry).
                        // Immediate reset would let a connect→die-within-1s cycle
                        // hammer the bridge at the minimum delay forever; no reset at
                        // all lets the counter accumulate across unrelated disconnects
                        // until reconnection dies silently.
                        self.backoffResetTask?.cancel()
                        if state == .connected {
                            self.backoffResetTask = Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                guard !Task.isCancelled else { return }
                                self?.bridgeManager?.reconnectAttempts = 0
                            }
                        }
                        bm.isSSEConnected = (state == .connected)

                        // Reconnect on any non-fatal terminal state. .disconnected covers
                        // network loss and normal stream end; .error covers HTTP 5xx and
                        // generic URL errors. Skip fatal config errors (bad URL, auth).
                        let shouldReconnect: Bool = {
                            switch state {
                            case .disconnected:
                                return true
                            case .error(let message):
                                if message == "Invalid URL" { return false }
                                if message.hasPrefix("HTTP 401") { return false }
                                if message.hasPrefix("HTTP 403") { return false }
                                return true
                            default:
                                return false
                            }
                        }()

                        if shouldReconnect, !self.isReconnectScheduled,
                           bm.reconnectAttempts < self.maxReconnectAttempts {
                            self.isReconnectScheduled = true
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
        AppLogger.sse.info("Stopping SSE event listener")
        eventSubscription?.cancel()
        streamStateSubscription?.cancel()
        eventSubscription = nil
        streamStateSubscription = nil
        backoffResetTask?.cancel()
        backoffResetTask = nil

        if let bm = bridgeManager {
            bm.isSSEConnected = false
            bm.reconnectAttempts = 0
        }
    }

    /// Manually reconnect SSE stream (for user-initiated reconnection).
    public func reconnectSSE() async {
        guard let bm = bridgeManager else { return }

        guard bm.isConnected else {
            AppLogger.sse.warning("Cannot reconnect SSE - no bridge connected")
            return
        }

        if bm.isSSEConnected {
            AppLogger.sse.info("SSE already connected - skipping reconnection")
            return
        }

        AppLogger.sse.debug("Manually reconnecting SSE stream...")

        stopListeningToSSEEvents()
        bm.reconnectAttempts = 0
        startListeningToSSEEvents()

        do {
            try await HueAPIService.shared.startEventStream()
            AppLogger.sse.info("SSE stream reconnected successfully")
        } catch {
            AppLogger.sse.error("Failed to reconnect SSE stream: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Event Processing

    /// Process incoming SSE events and update local state.
    private func processSSEEvents(_ events: [SSEEvent]) async {
        let relevantUpdates = events.relevantUpdates

        guard !relevantUpdates.isEmpty else { return }

        AppLogger.sse.debug("Processing \(relevantUpdates.count, privacy: .public) relevant event(s)")

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
        AppLogger.sse.debug("Grouped light update: \(data.debugDescription, privacy: .public)")

        let groupedLightId = data.id
        let on = data.on?.on
        let brightness = data.dimming?.brightness
        // Forward color so live-color UI stays in sync (mirek only when non-nil:
        // the bridge sends mirek: null while in xy mode)
        let colorXY = data.color.map {
            HueGroupedLight.GroupedLightColor.GroupedLightColorXY(x: $0.xy.x, y: $0.xy.y)
        }
        let mirek = data.colorTemperature?.mirek

        if let roomId = groupedLightToRoomMap[groupedLightId] {
            await MainActor.run {
                bm.updateLocalRoomState(roomId: roomId, on: on, brightness: brightness, colorXY: colorXY, mirek: mirek)
            }
            AppLogger.sse.debug("Updated room \(roomId, privacy: .public)")
        }

        if let zoneId = groupedLightToZoneMap[groupedLightId] {
            await MainActor.run {
                bm.updateLocalZoneState(zoneId: zoneId, on: on, brightness: brightness, colorXY: colorXY, mirek: mirek)
            }
            AppLogger.sse.debug("Updated zone \(zoneId, privacy: .public)")
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
                AppLogger.sse.debug("Updated \(label, privacy: .public) '\(name, privacy: .public)' metadata")
            }
        }
    }

    /// Handle room metadata update event.
    private func handleRoomUpdate(_ data: SSEEventData) async {
        guard let bm = bridgeManager else { return }
        AppLogger.sse.debug("Room update: \(data.debugDescription, privacy: .public)")
        await MainActor.run {
            self.handleGroupMetadataUpdate(data, in: &bm.rooms, label: "room")
        }
    }

    /// Handle zone metadata update event.
    private func handleZoneUpdate(_ data: SSEEventData) async {
        guard let bm = bridgeManager else { return }
        AppLogger.sse.debug("Zone update: \(data.debugDescription, privacy: .public)")
        await MainActor.run {
            self.handleGroupMetadataUpdate(data, in: &bm.zones, label: "zone")
        }
    }

    /// Handle scene status update event.
    private func handleSceneUpdate(_ data: SSEEventData) async {
        AppLogger.sse.debug("Scene update: \(data.debugDescription, privacy: .public)")
        if let status = data.status?.active {
            AppLogger.sse.debug("Scene \(data.id.prefix(8), privacy: .public) is now: \(status, privacy: .public)")
        }
    }

    // MARK: - Reconnection

    /// Handle auto-reconnection with exponential backoff.
    /// Called from a detached Task to prevent blocking MainActor.
    private func handleReconnection() async {
        // Allow the next disconnect/error event to schedule a fresh attempt
        // once this one has fully finished (including the backoff sleep).
        defer { isReconnectScheduled = false }

        let shouldSkip = await MainActor.run { [weak self] () -> Bool in
            guard let self = self, let bm = self.bridgeManager else { return true }
            return bm.isDemoMode || bm.connectedBridge == nil
        }

        if shouldSkip {
            AppLogger.sse.warning("Skipping SSE reconnection - no active bridge connection")
            return
        }

        let (currentAttempt, delay) = await MainActor.run { [weak self] () -> (Int, Double) in
            guard let self = self, let bm = self.bridgeManager else { return (0, 1.0) }
            bm.reconnectAttempts += 1
            let delay = min(pow(2.0, Double(bm.reconnectAttempts - 1)), 32.0)
            return (bm.reconnectAttempts, delay)
        }

        AppLogger.sse.debug("SSE disconnected. Reconnecting in \(Int(delay), privacy: .public)s (attempt \(currentAttempt, privacy: .public)/\(self.maxReconnectAttempts, privacy: .public))")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let bridgeStillConnected = await MainActor.run { [weak self] () -> Bool in
            guard let self = self, let bm = self.bridgeManager else { return false }
            return bm.connectedBridge != nil
        }

        guard bridgeStillConnected else {
            AppLogger.sse.warning("Bridge disconnected during reconnection delay - aborting")
            return
        }

        do {
            try await HueAPIService.shared.startEventStream()
            // NOTE: startEventStream() only spawns the stream task — returning is
            // not success, so do NOT reset reconnectAttempts here. The stream-state
            // sink resets the counter once the connection proves stable.
            AppLogger.sse.info("SSE stream reconnected")
        } catch {
            AppLogger.sse.error("Failed to reconnect SSE stream: \(error.localizedDescription, privacy: .public)")
        }
    }
}
