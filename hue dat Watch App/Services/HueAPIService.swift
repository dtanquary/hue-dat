//
//  BridgeConnectionService.swift
//  hue dat
//
//  Created by David Tanquary on 11/9/25.
//

import Foundation
import Combine

// MARK: - API Errors
enum HueAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
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

// MARK: - API Response Models
struct HueAPIV2Error: Decodable, Sendable {
    let description: String
}

// Non-isolated wrapper for rooms response
// BridgeManager.HueRoom is MainActor-isolated, so we use a custom Decodable implementation
struct HueRoomsResponse {
    let errors: [HueAPIV2Error]
    let data: [BridgeManager.HueRoom]
}

// Manual Decodable conformance to avoid actor isolation issues
extension HueRoomsResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case errors
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.errors = try container.decode([HueAPIV2Error].self, forKey: .errors)
        self.data = try container.decode([BridgeManager.HueRoom].self, forKey: .data)
    }
}

// Non-isolated wrapper for zones response
// BridgeManager.HueZone is MainActor-isolated, so we use a custom Decodable implementation
struct HueZonesResponse {
    let errors: [HueAPIV2Error]
    let data: [BridgeManager.HueZone]
}

// Manual Decodable conformance to avoid actor isolation issues
extension HueZonesResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case errors
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.errors = try container.decode([HueAPIV2Error].self, forKey: .errors)
        self.data = try container.decode([BridgeManager.HueZone].self, forKey: .data)
    }
}

// Non-isolated wrapper for grouped lights response
// BridgeManager.HueGroupedLight is MainActor-isolated, so we use a custom Decodable implementation
struct HueGroupedLightsResponse {
    let errors: [HueAPIV2Error]
    let data: [BridgeManager.HueGroupedLight]
}

// Manual Decodable conformance to avoid actor isolation issues
extension HueGroupedLightsResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case errors
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.errors = try container.decode([HueAPIV2Error].self, forKey: .errors)
        self.data = try container.decode([BridgeManager.HueGroupedLight].self, forKey: .data)
    }
}

// MARK: - Stream State
enum StreamState: Equatable {
    case idle
    case connecting
    case connected
    case disconnected(Error?)
    case error(String)

    static func == (lhs: StreamState, rhs: StreamState) -> Bool {
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

actor HueAPIService {
    static let shared = HueAPIService()

    let session: URLSession
    private let sessionDelegate: InsecureURLSessionDelegate
    private var streamTask: Task<Void, Never>?

    var baseURL = ""
    var hueApplicationKey = ""

    // Combine publisher for stream state changes (thread-safe)
    let streamStateSubject = PassthroughSubject<StreamState, Never>()

    // Combine publisher for parsed SSE events (thread-safe)
    let eventPublisher = PassthroughSubject<[SSEEvent], Never>()

    // Rate limiting state
    private var lastGroupedLightUpdate: [String: Date] = [:] // Track per-light last update
    private let groupedLightRateLimit: TimeInterval = 1.0 // 1 second between updates for grouped lights
    private let individualLightRateLimit: TimeInterval = 0.1 // 10 per second for individual lights

    init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1

        // Prevent stream timeouts
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        config.waitsForConnectivity = true

        self.sessionDelegate = InsecureURLSessionDelegate()
        self.session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    func setup(baseUrl: String, hueApplicationKey: String) {
        self.baseURL = baseUrl
        self.hueApplicationKey = hueApplicationKey
    }

    // MARK: - REST API Methods

    /// Generic REST API request method
    /// Uses the same session as SSE streaming for HTTP/2 multiplexing
    func request<T: Decodable>(
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

        let (data, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Failed to decode response. Raw data: \(responseString)")
            }
            throw HueAPIError.decodingError(error)
        }
    }

    /// Fetch all rooms from the bridge
    /// Returns: HueRoomsResponse containing array of rooms
    func fetchRooms() async throws -> HueRoomsResponse {
        // Fetch raw data first
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/room") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let (data, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode outside actor context
        // Note: This generates a Swift 6 warning because BridgeManager.HueRoom is MainActor-isolated
        // The warning is harmless - decoding is safe in a detached task
        return try await Task.detached {
            do {
                return try JSONDecoder().decode(HueRoomsResponse.self, from: data)
            } catch {
                // Log raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Failed to decode rooms response. Raw data: \(responseString)")
                }
                throw HueAPIError.decodingError(error)
            }
        }.value
    }

    /// Fetch all zones from the bridge
    /// Returns: HueZonesResponse containing array of zones
    func fetchZones() async throws -> HueZonesResponse {
        // Fetch raw data first
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/zone") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let (data, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode outside actor context
        // Note: This generates a Swift 6 warning because BridgeManager.HueZone is MainActor-isolated
        // The warning is harmless - decoding is safe in a detached task
        return try await Task.detached {
            do {
                return try JSONDecoder().decode(HueZonesResponse.self, from: data)
            } catch {
                // Log raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Failed to decode zones response. Raw data: \(responseString)")
                }
                throw HueAPIError.decodingError(error)
            }
        }.value
    }

    /// Fetch all grouped lights from the bridge
    /// Returns: HueGroupedLightsResponse containing array of grouped lights
    func fetchGroupedLights() async throws -> HueGroupedLightsResponse {
        // Fetch raw data first
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/grouped_light") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let (data, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode outside actor context
        // Note: This generates a Swift 6 warning because BridgeManager.HueGroupedLight is MainActor-isolated
        // The warning is harmless - decoding is safe in a detached task
        return try await Task.detached {
            do {
                return try JSONDecoder().decode(HueGroupedLightsResponse.self, from: data)
            } catch {
                // Log raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Failed to decode grouped lights response. Raw data: \(responseString)")
                }
                throw HueAPIError.decodingError(error)
            }
        }.value
    }

    // MARK: - Control Methods

    /// Check and enforce rate limit for grouped light
    /// Returns: true if request should proceed, false if rate limited
    private func checkGroupedLightRateLimit(groupedLightId: String) async -> Bool {
        let now = Date()

        if let lastUpdate = lastGroupedLightUpdate[groupedLightId] {
            let timeSinceLastUpdate = now.timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < groupedLightRateLimit {
                // Rate limited - wait for remaining time
                let waitTime = groupedLightRateLimit - timeSinceLastUpdate
                print("⏱️ Rate limiting grouped light \(groupedLightId): waiting \(String(format: "%.1f", waitTime))s")
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }

        lastGroupedLightUpdate[groupedLightId] = Date()
        return true
    }

    /// Set power state for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - on: true to turn on, false to turn off
    func setPower(groupedLightId: String, on: Bool) async throws {
        // Enforce rate limit
        _ = await checkGroupedLightRateLimit(groupedLightId: groupedLightId)

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

        let (_, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Set power: \(on ? "ON" : "OFF") for grouped light \(groupedLightId)")
    }

    /// Set brightness for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - brightness: Brightness percentage (0.0 to 100.0)
    func setBrightness(groupedLightId: String, brightness: Double) async throws {
        // Enforce rate limit
        _ = await checkGroupedLightRateLimit(groupedLightId: groupedLightId)

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

        let (_, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Set brightness: \(brightness)% for grouped light \(groupedLightId)")
    }

    /// Adjust brightness relatively for a grouped light (room or zone)
    /// - Parameters:
    ///   - groupedLightId: The grouped light ID from room/zone services
    ///   - delta: Relative brightness change (-100.0 to +100.0)
    func adjustBrightness(groupedLightId: String, delta: Double) async throws {
        // Enforce rate limit
        _ = await checkGroupedLightRateLimit(groupedLightId: groupedLightId)

        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource/grouped_light/\(groupedLightId)") else {
            throw HueAPIError.invalidURL
        }

        // Build JSON payload with dimming_delta
        // Note: This structure is based on logical API patterns; actual Hue API v2 support needs verification
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

        let (_, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Adjusted brightness: \(delta > 0 ? "+" : "")\(delta)% for grouped light \(groupedLightId)")
    }

    // MARK: - Scene Methods

    /// Fetch all scenes from the bridge
    /// Returns: Generic Decodable response (typically used with BridgeManager.HueScene)
    func fetchScenes<T: Decodable>() async throws -> T {
        return try await request(endpoint: "/clip/v2/resource/scene", method: "GET", timeout: 10.0)
    }

    /// Activate a scene
    /// - Parameters:
    ///   - sceneId: The scene ID to activate
    func activateScene(sceneId: String) async throws {
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

        let (_, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Activated scene \(sceneId)")
    }

    // MARK: - Connection Validation

    /// Validate connection to the bridge
    /// Returns: true if connection is valid, throws error otherwise
    func validateConnection() async throws -> Bool {
        guard let url = URL(string: "https://\(baseURL)/clip/v2/resource") else {
            throw HueAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hueApplicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let (_, response) = try await session.data(for: request, delegate: sessionDelegate)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HueAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        print("✅ Connection validated")
        return true
    }

    // MARK: - Streaming Methods

    func startEventStream() async throws {
        // Cancel any existing stream
        streamTask?.cancel()

        // Start new stream task
        streamTask = Task {
            await streamEvents()
        }
    }

    func stopEventStream() {
        streamTask?.cancel()
        streamTask = nil
        streamStateSubject.send(.idle)
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
            let (bytes, response) = try await session.bytes(for: request, delegate: sessionDelegate)

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
                print("⚠️ Warning: Expected text/event-stream, got \(contentType)")
            }

            streamStateSubject.send(.connected)
            print("✅ SSE stream connected (HTTP/2 multiplexing enabled)")

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
                                    print("📦 Parsed \(events.count) SSE event(s)")
                                    // Publish to subscribers
                                    eventPublisher.send(events)
                                }
                            } catch {
                                print("⚠️ Failed to parse SSE event JSON: \(error)")
                                print("  Raw data: \(jsonString.prefix(200))...")
                            }
                        }
                    }
                } else if line.hasPrefix(":") {
                    // SSE comment (keepalive) - ignore
                    continue
                } else if line.hasPrefix("event:") {
                    // Event type - could track this if needed
                    print("🏷️ Event type: \(line.dropFirst(6))")
                } else if line.hasPrefix("id:") {
                    // Event ID - could track for reconnection
                    continue
                } else if line.isEmpty {
                    // Empty line separates events - ignore
                    continue
                } else {
                    // Unknown SSE field
                    print("❓ Unknown SSE field: \(line)")
                }
            }

            // Stream ended normally
            streamStateSubject.send(.disconnected(nil))
            print("ℹ️ SSE stream ended")

        } catch is CancellationError {
            streamStateSubject.send(.disconnected(nil))
            print("ℹ️ SSE stream cancelled")
        } catch {
            streamStateSubject.send(.error("Stream error: \(error.localizedDescription)"))
            print("❌ SSE stream error: \(error)")
        }
    }
}
