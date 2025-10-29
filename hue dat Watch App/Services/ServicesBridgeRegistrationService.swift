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
        registeringBridge = bridge
        error = nil
        successfulBridge = nil
        registrationResponse = nil
        showLinkButtonAlert = false
        linkButtonBridge = nil
        
        do {
            let registrationResult = try await performBridgeRegistration(bridge: bridge)
            print("Registration successful: \(registrationResult)")
            registrationResponse = registrationResult
            successfulBridge = bridge
        } catch {
            // Check if this is a "link button not pressed" error
            if let errorData = error as? BridgeRegistrationError,
               case .linkButtonNotPressed = errorData {
                linkButtonBridge = bridge
                showLinkButtonAlert = true
            } else {
                self.error = error
            }
        }
        
        registeringBridge = nil
    }
    
    private func performBridgeRegistration(bridge: BridgeInfo) async throws -> BridgeRegistrationResponse {
        // For production, uncomment the network call:
        /*
        let url = URL(string: "https://\(bridge.displayAddress)/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "devicetype": "hue_dat_watch_app#\(WKInterfaceDevice.current().name)",
            "generateclientkey": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Parse the response array and extract the success object
        if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstResponse = jsonArray.first,
           let successData = firstResponse["success"] as? [String: Any] {
            let successJson = try JSONSerialization.data(withJSONObject: successData)
            return try JSONDecoder().decode(BridgeRegistrationResponse.self, from: successJson)
        } else {
            throw URLError(.cannotParseResponse)
        }
        */
        
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
    }
    
    // Helper methods for demo link button flow
    private func hasAttemptedLinkButton(for bridge: BridgeInfo) -> Bool {
        return linkButtonAttempts.contains(bridge.id)
    }
    
    private func markLinkButtonAttempt(for bridge: BridgeInfo) {
        linkButtonAttempts.insert(bridge.id)
    }
}