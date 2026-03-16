//
//  BridgeRegistrationService.swift
//  HueDatShared
//
//  Created by David Tanquary on 10/29/25.
//

import Foundation
import Observation
import os

// MARK: - Bridge Registration Service
@MainActor
@Observable
public class BridgeRegistrationService {
    public var error: Error?
    public var registeringBridge: BridgeInfo?
    public var successfulBridge: BridgeInfo?
    public var registrationResponse: BridgeRegistrationResponse?
    public var showLinkButtonAlert = false
    public var linkButtonBridge: BridgeInfo?

    @ObservationIgnored private let deviceIdentifierProvider: DeviceIdentifierProvider

    // Helper for demo link button flow
    @ObservationIgnored private var linkButtonAttempts: Set<String> = []

    public init(deviceIdentifierProvider: DeviceIdentifierProvider) {
        self.deviceIdentifierProvider = deviceIdentifierProvider
    }

    public var hasActiveRegistration: Bool {
        registeringBridge != nil
    }

    public func isRegistering(bridge: BridgeInfo) -> Bool {
        registeringBridge?.id == bridge.id
    }

    public func isRegistered(bridge: BridgeInfo) -> Bool {
        successfulBridge?.id == bridge.id
    }

    public func clearSuccess() {
        successfulBridge = nil
        registrationResponse = nil
    }

    public func clearLinkButtonAlert() {
        showLinkButtonAlert = false
        linkButtonBridge = nil
    }

    public func registerWithBridge(_ bridge: BridgeInfo) async {
        await MainActor.run {
            registeringBridge = bridge
            error = nil
            successfulBridge = nil
            registrationResponse = nil
            showLinkButtonAlert = false
            linkButtonBridge = nil
        }

        do {
            let registrationResult = try await performBridgeRegistration(bridge: bridge)
            AppLogger.registration.info("Registration successful")
            await MainActor.run {
                registrationResponse = registrationResult
                successfulBridge = bridge
            }
        } catch {
            await MainActor.run {
                // Check if this is a "link button not pressed" error
                if let errorData = error as? BridgeRegistrationError,
                   case .linkButtonNotPressed = errorData {
                    linkButtonBridge = bridge
                    showLinkButtonAlert = true
                } else {
                    self.error = error
                }
            }
        }

        await MainActor.run {
            registeringBridge = nil
        }
    }

    private func performBridgeRegistration(bridge: BridgeInfo) async throws -> BridgeRegistrationResponse {
        // Get unique device identifier using platform-specific provider
        let deviceId = deviceIdentifierProvider.getDeviceIdentifier()?.uuidString.prefix(8) ?? "unknown"
        let urlString = "https://\(bridge.internalipaddress)/api"

        // Usage
        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            throw BridgeRegistrationError.bridgeError("Invalid bridge URL: \(bridge.internalipaddress)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Your payload with unique device identifier
        let payload: [String: Any] = [
            "devicetype": "hue_dat_watch_app#\(deviceId)",
            "generateclientkey": true
        ]

        AppLogger.registration.debug("Registration payload prepared for bridge \(bridge.displayName, privacy: .public)")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard response is HTTPURLResponse else {
            throw BridgeRegistrationError.bridgeError("Invalid response type")
        }

        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            AppLogger.registration.debug("Raw response: \(responseString, privacy: .private)")
        }

        // Parse the JSON response
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            AppLogger.registration.error("Failed to parse JSON response as array")
            throw BridgeRegistrationError.bridgeError("Invalid JSON response format")
        }

        AppLogger.registration.debug("Parsed JSON array with \(jsonArray.count, privacy: .public) items")

        // Check if the first response contains an error
        if let firstResponse = jsonArray.first,
           let errorData = firstResponse["error"] as? [String: Any] {
            let errorType = errorData["type"] as? Int ?? 0
            let description = errorData["description"] as? String ?? "Unknown error"
            AppLogger.registration.warning("Bridge returned error - Type: \(errorType, privacy: .public), Description: \(description, privacy: .public)")

            if errorType == 101 {
                // This is the "link button not pressed" error
                throw BridgeRegistrationError.linkButtonNotPressed(description)
            } else {
                throw BridgeRegistrationError.bridgeError("Bridge error (\(errorType)): \(description)")
            }
        }

        // Look for success response
        if let firstResponse = jsonArray.first,
           let successData = firstResponse["success"] as? [String: Any] {
            AppLogger.registration.info("Success data received")
            let successJson = try JSONSerialization.data(withJSONObject: successData)
            let registrationResponse = try JSONDecoder().decode(BridgeRegistrationResponse.self, from: successJson)
            #if DEBUG
            AppLogger.registration.debug("Parsed registration response - Username: \(registrationResponse.username, privacy: .private), ClientKey: \(registrationResponse.clientkey ?? "nil", privacy: .private)")
            #endif
            return registrationResponse
        }

        // If we get here, it's an unexpected response format
        AppLogger.registration.error("Unexpected response format")
        throw BridgeRegistrationError.bridgeError("Unexpected response format: expected success or error response")
    }
}
