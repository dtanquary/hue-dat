//
//  HueAPIService.swift
//  HueDatShared
//
//  Actor-based API service for Hue bridge communication with SSE streaming
//

import Foundation
import Combine
import os

// MARK: - API Errors

public enum HueAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from bridge"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Stream State

public enum StreamState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected(Error?)
    case error(String)

    public static func == (lhs: StreamState, rhs: StreamState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.disconnected, .disconnected),
             (.error, .error):
            return true
        default:
            return false
        }
    }
}

// MARK: - Hue API Service

public actor HueAPIService {
    public static let shared = HueAPIService()

    /// REST session: finite timeouts, fails fast on network loss
    private let restSession: URLSession
    private let restSessionDelegate: InsecureURLSessionDelegate

    /// SSE streaming session: infinite timeouts, waits for connectivity
    private let streamSession: URLSession
    private let streamSessionDelegate: InsecureURLSessionDelegate

    private var streamTask: Task<Void, Never>?

    public var baseURL = ""
    public var hueApplicationKey = ""

    // Combine publisher for stream state changes (thread-safe)
    public let streamStateSubject = PassthroughSubject<StreamState, Never>()

    // Combine publisher for parsed SSE events (thread-safe)
    public let eventPublisher = PassthroughSubject<[SSEEvent], Never>()

    // Rate limiting state
    private var lastGroupedLightUpdate: [String: Date] = [:] // Track per-light last update
    private let groupedLightRateLimit: TimeInterval = 1.0 // 1 second between updates for grouped lights
    private let individualLightRateLimit: TimeInterval = 0.1 // 10 per second for individual lights

    public init() {
        // REST session: short timeouts, no waiting for connectivity.
        // When network drops, REST calls fail immediately instead of hanging.
        let restConfig = URLSessionConfiguration.default
        restConfig.timeoutIntervalForRequest = 10.0
        restConfig.timeoutIntervalForResource = 15.0
        restConfig.waitsForConnectivity = false
        self.restSessionDelegate = InsecureURLSessionDelegate()
        self.restSession = URLSession(configuration: restConfig, delegate: restSessionDelegate, delegateQueue: nil)

        // SSE streaming session: infinite timeouts for long-lived event stream.
        let streamConfig = URLSessionConfiguration.default
        streamConfig.httpMaximumConnectionsPerHost = 1
        streamConfig.timeoutIntervalForRequest = .infinity
        streamConfig.timeoutIntervalForResource = .infinity
        streamConfig.waitsForConnectivity = true
        self.streamSessionDelegate = InsecureURLSessionDelegate()
        self.streamSession = URLSession(configuration: streamConfig, delegate: streamSessionDelegate, delegateQueue: nil)
    }

    public func setup(baseUrl: String, hueApplicationKey: String) {
        self.baseURL = baseUrl
        self.hueApplicationKey = hueApplicationKey
    }

    // MARK: - REST API Methods

    /// Generic REST API request method
    /// Uses the same session as SSE streaming for HTTP/2 multiplexing
    public func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 10.0
    ) async throws -> T {
        guard let url = URL(string: "https://\(baseURL)\(endpoint)") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout  // Override session's infinite timeout for REST calls

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode outside actor context to avoid blocking the actor
        return try await Task.detached {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                // Log raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    AppLogger.api.error("Failed to decode response. Raw data: \(responseString, privacy: .private)")
                }
                throw HueAPIError.decodingError(error)
            }
        }.value
    }

    /// Fetch all rooms from the bridge
    /// Returns: HueRoomsResponse containing array of rooms
    public func fetchRooms() async throws -> HueRoomsResponse {
        return try await request(endpoint: "/clip/v2/resource/room")
    }

    /// Fetch all zones from the bridge
    /// Returns: HueZonesResponse containing array of zones
    public func fetchZones() async throws -> HueZonesResponse {
        return try await request(endpoint: "/clip/v2/resource/zone")
    }

    /// Fetch all grouped lights from the bridge
    /// Returns: HueGroupedLightsResponse containing array of grouped lights
    public func fetchGroupedLights() async throws -> HueGroupedLightsResponse {
        return try await request(endpoint: "/clip/v2/resource/grouped_light")
    }

    /// Fetch a single grouped light by ID
    /// Returns: The grouped light, or nil if not found
    public func fetchGroupedLight(groupedLightId: String) async throws -> HueGroupedLight? {
        let response: HueGroupedLightsResponse = try await request(
            endpoint: "/clip/v2/resource/grouped_light/\(groupedLightId)"
        )
        return response.data.first
    }

    // MARK: - Control Methods

    /// Check rate limit for grouped light operations (non-blocking)
    /// Returns: true if request should proceed, false if rate limited (call will be dropped)
    private func checkGroupedLightRateLimit(groupedLightId: String) -> Bool {
        let now = Date()

        if let lastUpdate = lastGroupedLightUpdate[groupedLightId] {
            let timeSinceLastUpdate = now.timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < groupedLightRateLimit {
                // Rate limited - drop this request
                AppLogger.api.debug("Dropping grouped light update for \(groupedLightId, privacy: .public): too soon (\(String(format: "%.1f", timeSinceLastUpdate), privacy: .public)s since last)")
                return false
            }
        }

        // Update timestamp and allow request
        lastGroupedLightUpdate[groupedLightId] = now
        return true
    }

    /// Set power state for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - on: true to turn on, false to turn off
    public func setPower(groupedLightId: String, on: Bool) async throws {
        // No rate limiting for power toggles - instant feedback is critical for UX

        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/grouped_light/\(groupedLightId)") else {
            throw HueAPIError.invalidURL
        }

        // Build JSON payload
        let payload: [String: Any] = [
            "on": ["on": on]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw HueAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        request.httpBody = jsonData

        let (_, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        AppLogger.api.info("Set power: \(on ? "ON" : "OFF", privacy: .public) for grouped light \(groupedLightId, privacy: .public)")
    }

    /// Set brightness for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - brightness: Brightness percentage (0.0 to 100.0)
    public func setBrightness(groupedLightId: String, brightness: Double) async throws {
        // Check rate limit (non-blocking - drops rapid calls)
        guard checkGroupedLightRateLimit(groupedLightId: groupedLightId) else {
            return // Drop this call - too soon since last update
        }

        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/grouped_light/\(groupedLightId)") else {
            throw HueAPIError.invalidURL
        }

        // Build JSON payload
        let payload: [String: Any] = [
            "dimming": ["brightness": brightness]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw HueAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        request.httpBody = jsonData

        let (_, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        AppLogger.api.info("Set brightness: \(brightness, privacy: .public)% for grouped light \(groupedLightId, privacy: .public)")
    }

    /// Adjust brightness relatively for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - delta: Relative brightness change (-100.0 to +100.0)
    public func adjustBrightness(groupedLightId: String, delta: Double) async throws {
        // Check rate limit (non-blocking - drops rapid calls)
        guard checkGroupedLightRateLimit(groupedLightId: groupedLightId) else {
            return // Drop this call - too soon since last update
        }

        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/grouped_light/\(groupedLightId)") else {
            throw HueAPIError.invalidURL
        }

        // Build JSON payload with dimming_delta (confirmed working with Hue API v2)
        let payload: [String: Any] = [
            "dimming_delta": [
                "action": delta >= 0 ? "up" : "down",
                "brightness_delta": abs(delta)
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw HueAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        request.httpBody = jsonData

        let (_, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        AppLogger.api.info("Adjusted brightness: \(delta > 0 ? "+" : "", privacy: .public)\(delta, privacy: .public)% for grouped light \(groupedLightId, privacy: .public)")
    }

    // MARK: - Scene Methods

    /// Fetch all scenes from the bridge
    /// Returns: HueScenesResponse containing array of scenes
    public func fetchScenes() async throws -> HueScenesResponse {
        return try await request(endpoint: "/clip/v2/resource/scene", method: "GET", timeout: 10.0)
    }

    /// Activate a scene
    /// - Parameters:
    ///   - sceneId: The scene ID to activate
    public func activateScene(sceneId: String) async throws {
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/scene/\(sceneId)") else {
            throw HueAPIError.invalidURL
        }

        // Build JSON payload
        let payload: [String: Any] = [
            "recall": ["action": "active"]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw HueAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        request.httpBody = jsonData

        let (_, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        AppLogger.api.info("Activated scene \(sceneId, privacy: .public)")
    }

    // MARK: - Connection Validation

    /// Validate connection to the bridge
    /// Returns: true if connection is valid, throws error otherwise
    public func validateConnection() async throws -> Bool {
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let (_, response) = try await restSession.data(for: request, delegate: restSessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        return true
    }

    // MARK: - Streaming Methods

    public func startEventStream() async throws {
        // Cancel any existing stream
        streamTask?.cancel()

        // Start new stream task
        streamTask = Task {
            await streamEvents()
        }
    }

    public func stopEventStream() {
        streamTask?.cancel()
        streamTask = nil
        streamStateSubject.send(.idle)
        AppLogger.sse.info("SSE stream stopped and cleaned up")
    }

    private func streamEvents() async {
        guard let url = URL(string: "https://\(baseURL)/eventstream/clip/v2") else {
            streamStateSubject.send(.error("Invalid URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")

        streamStateSubject.send(.connecting)

        do {
            let (bytes, response) = try await streamSession.bytes(for: request, delegate: streamSessionDelegate)

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                streamStateSubject.send(.error("Invalid response type"))
                return
            }

            guard httpResponse.statusCode == 200 else {
                streamStateSubject.send(.error("HTTP \(httpResponse.statusCode)"))
                return
            }

            // Verify content type
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.contains("text/event-stream") {
                AppLogger.sse.warning("Expected text/event-stream, got \(contentType, privacy: .public)")
            }

            streamStateSubject.send(.connected)
            AppLogger.sse.info("SSE stream connected (HTTP/2 multiplexing enabled)")

            // Process SSE stream
            for try await line in bytes.lines {
                // Parse SSE format
                if line.hasPrefix("data:") {
                    let jsonString = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                    if !jsonString.isEmpty {
                        // Parse JSON data and publish events
                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                let events = try JSONDecoder().decode([SSEEvent].self, from: jsonData)
                                if !events.isEmpty {
                                    AppLogger.sse.debug("Parsed \(events.count, privacy: .public) SSE event(s)")
                                    // Publish to subscribers
                                    eventPublisher.send(events)
                                }
                            } catch {
                                AppLogger.sse.warning("Failed to parse SSE event JSON: \(error.localizedDescription, privacy: .public)")
                                AppLogger.sse.debug("Raw data: \(jsonString.prefix(200), privacy: .private)...")
                            }
                        }
                    }
                } else if line.hasPrefix(":") {
                    // SSE comment (keepalive) - ignore
                    continue
                } else if line.hasPrefix("event:") {
                    // Event type - could track this if needed
                    AppLogger.sse.debug("Event type: \(line.dropFirst(6), privacy: .public)")
                } else if line.hasPrefix("id:") {
                    // Event ID - could track for reconnection
                    continue
                } else if line.isEmpty {
                    // Empty line separates events - ignore
                    continue
                } else {
                    // Unknown SSE field
                    AppLogger.sse.warning("Unknown SSE field: \(line, privacy: .public)")
                }
            }

            // Stream ended normally
            streamStateSubject.send(.disconnected(nil))
            AppLogger.sse.info("SSE stream ended")

        } catch is CancellationError {
            // Clean cancellation
            streamStateSubject.send(.disconnected(nil))
            AppLogger.sse.info("SSE stream cancelled")
        } catch let error as URLError where error.code == .networkConnectionLost {
            // Network connection lost - common during network transitions
            AppLogger.sse.warning("SSE stream: Network connection lost (bridge may have reset connection)")
            streamStateSubject.send(.disconnected(error))
        } catch {
            // Other errors
            AppLogger.sse.error("SSE stream error: \(error.localizedDescription, privacy: .public)")
            streamStateSubject.send(.error("Stream error: \(error.localizedDescription)"))
        }
    }
}
