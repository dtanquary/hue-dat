//
//  BridgeRegistrationService.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import WatchKit
import Combine

// MARK: - Bridge Registration Service
@MainActor
class BridgeRegistrationService: ObservableObject {
    @Published var error: Error?
    @Published var registeringBridge: BridgeInfo?
    @Published var successfulBridge: BridgeInfo?
    @Published var registrationResponse: BridgeRegistrationResponse?
    @Published var showLinkButtonAlert = false
    @Published var linkButtonBridge: BridgeInfo?
    
    // Helper for demo link button flow
    private var linkButtonAttempts: Set<String> = []
    
    var hasActiveRegistration: Bool {
        registeringBridge != nil
    }
    
    func isRegistering(bridge: BridgeInfo) -> Bool {
        registeringBridge?.id == bridge.id
    }
    
    func isRegistered(bridge: BridgeInfo) -> Bool {
        successfulBridge?.id == bridge.id
    }
    
    func clearSuccess() {
        successfulBridge = nil
        registrationResponse = nil
    }
    
    func clearLinkButtonAlert() {
        showLinkButtonAlert = false
        linkButtonBridge = nil
    }
    
    func registerWithBridge(_ bridge: BridgeInfo) async {
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
        let testSuffix = "test1"
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
        
        // Your payload
        let payload: [String: Any] = [
            "devicetype": "hue_dat_watch_app#\(testSuffix)",
            "generateclientkey": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeRegistrationError.bridgeError("Invalid response type")
        }
        
        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Response: \(responseString)")
        }
        
        // Parse the JSON response
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BridgeRegistrationError.bridgeError("Invalid JSON response format")
        }
        
        // Check if the first response contains an error
        if let firstResponse = jsonArray.first,
           let errorData = firstResponse["error"] as? [String: Any],
           let errorType = errorData["type"] as? Int,
           errorType == 101 {
            // This is the "link button not pressed" error
            let description = errorData["description"] as? String ?? "link button not pressed"
            throw BridgeRegistrationError.linkButtonNotPressed(description)
        }
        
        // Look for success response
        if let firstResponse = jsonArray.first,
           let successData = firstResponse["success"] as? [String: Any] {
            let successJson = try JSONSerialization.data(withJSONObject: successData)
            return try JSONDecoder().decode(BridgeRegistrationResponse.self, from: successJson)
        }
        
        // If we get here, it's an unexpected response format
        throw BridgeRegistrationError.bridgeError("Unexpected response format")
        
        /*
        // Simulate network delay for registration
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // For demo purposes, simulate the link button flow
        // First attempt: throw link button error if this is the first try for this bridge
        if !hasAttemptedLinkButton(for: bridge) {
            markLinkButtonAttempt(for: bridge)
            throw BridgeRegistrationError.linkButtonNotPressed("link button not pressed")
        }
        
        // Second attempt: return success
        return BridgeRegistrationResponse(
            username: "mock-username-\(UUID().uuidString.prefix(8))",
            clientkey: "mock-client-key-\(UUID().uuidString.prefix(16))"
        )
         */
    }
    
    // Helper methods for demo link button flow
    private func hasAttemptedLinkButton(for bridge: BridgeInfo) -> Bool {
        return linkButtonAttempts.contains(bridge.id)
    }
    
    private func markLinkButtonAttempt(for bridge: BridgeInfo) {
        linkButtonAttempts.insert(bridge.id)
    }
    
    // Helper method to detect IPv6 addresses
    private func isIPv6Address(_ ipAddress: String) -> Bool {
        // IPv6 addresses contain colons and are not IPv4 format
        return ipAddress.contains(":") && !ipAddress.contains(".")
    }
}

// MARK: - Insecure URL Session Delegate
class InsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept any certificate (insecure!)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: trust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
