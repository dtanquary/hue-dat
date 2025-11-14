//
//  BridgeRegistrationService.swift
//  HueDatShared
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Bridge Registration Service
@MainActor
public class BridgeRegistrationService: ObservableObject {
    @Published public var error: Error?
    @Published public var registeringBridge: BridgeInfo?
    @Published public var successfulBridge: BridgeInfo?
    @Published public var registrationResponse: BridgeRegistrationResponse?
    @Published public var showLinkButtonAlert = false
    @Published public var linkButtonBridge: BridgeInfo?

    private let deviceIdentifierProvider: DeviceIdentifierProvider

    // Helper for demo link button flow
    private var linkButtonAttempts: Set<String> = []

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
            print("Registration successful: \(registrationResult)")
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

        print("Payload: \(payload)")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard response is HTTPURLResponse else {
            throw BridgeRegistrationError.bridgeError("Invalid response type")
        }

        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Raw response: \(responseString)")
        }

        // Parse the JSON response
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("Failed to parse JSON response as array")
            throw BridgeRegistrationError.bridgeError("Invalid JSON response format")
        }

        print("Parsed JSON array with \(jsonArray.count) items")

        // Check if the first response contains an error
        if let firstResponse = jsonArray.first,
           let errorData = firstResponse["error"] as? [String: Any] {
            let errorType = errorData["type"] as? Int ?? 0
            let description = errorData["description"] as? String ?? "Unknown error"
            print("Bridge returned error - Type: \(errorType), Description: \(description)")

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
            print("Success data received: \(successData)")
            let successJson = try JSONSerialization.data(withJSONObject: successData)
            let registrationResponse = try JSONDecoder().decode(BridgeRegistrationResponse.self, from: successJson)
            print("Parsed registration response - Username: \(registrationResponse.username), ClientKey: \(registrationResponse.clientkey ?? "nil")")
            return registrationResponse
        }

        // If we get here, it's an unexpected response format
        print("Unexpected response format. First response: \(jsonArray.first ?? [:])")
        throw BridgeRegistrationError.bridgeError("Unexpected response format: expected success or error response")
    }
}
