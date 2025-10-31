//
//  BridgeManager.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Connection Validation Result
enum ConnectionValidationResult {
    case success
    case failure(message: String)
}

// MARK: - Bridge Manager
@MainActor
class BridgeManager: ObservableObject {
    @Published var connectedBridge: BridgeConnectionInfo?
    @Published var showAlert: Bool = false
    @Published var alertMessage: String? = nil
    @Published var isConnectionValidated: Bool = false
    
    // Event broadcasting for connection validation
    private let connectionValidationSubject = PassthroughSubject<ConnectionValidationResult, Never>()
    var connectionValidationPublisher: AnyPublisher<ConnectionValidationResult, Never> {
        connectionValidationSubject.eraseToAnyPublisher()
    }
    
    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    
    /// Returns the current connected bridge information, or nil if none is connected.
    var currentConnectedBridge: BridgeConnectionInfo? {
        connectedBridge
    }
    
    init() {
        loadConnectedBridge()
    }
    
    func saveConnection(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        let connectionInfo = BridgeConnectionInfo(bridge: bridge, registrationResponse: registrationResponse)
        
        do {
            let data = try JSONEncoder().encode(connectionInfo)
            userDefaults.set(data, forKey: connectedBridgeKey)
            
            // Force synchronize to ensure data is written immediately
            userDefaults.synchronize()
            
            connectedBridge = connectionInfo
            print("✅ Bridge connection saved successfully:")
            print("  - Bridge: \(bridge.displayName) (\(bridge.shortId))")
            print("  - Username: \(registrationResponse.username)")
            print("  - ClientKey: \(registrationResponse.clientkey ?? "nil")")
            print("  - Connected Date: \(connectionInfo.connectedDate)")
            print("  - Data size: \(data.count) bytes")
            
            // Verify the save by immediately reading it back
            if let verifyData = userDefaults.data(forKey: connectedBridgeKey) {
                print("✅ Verification: Data successfully retrieved from UserDefaults (\(verifyData.count) bytes)")
            } else {
                print("❌ Verification failed: Could not retrieve data from UserDefaults")
            }
        } catch {
            print("❌ Failed to save bridge connection: \(error)")
        }
    }
    
    func disconnectBridge() {
        userDefaults.removeObject(forKey: connectedBridgeKey)
        userDefaults.synchronize()
        connectedBridge = nil
        isConnectionValidated = false
        print("🔌 Bridge disconnected and cleared from storage")
    }
    
    private func loadConnectedBridge() {
        print("🔍 Loading bridge connection from UserDefaults...")
        
        guard let data = userDefaults.data(forKey: connectedBridgeKey) else {
            print("❌ No saved bridge connection found")
            return
        }
        
        print("📊 Found saved data: \(data.count) bytes")
        
        do {
            connectedBridge = try JSONDecoder().decode(BridgeConnectionInfo.self, from: data)
            if let connection = connectedBridge {
                print("✅ Loaded saved bridge connection:")
                print("  - Bridge: \(connection.bridge.shortId)")
                print("  - Address: \(connection.bridge.displayAddress)")
                print("  - Username: \(connection.username)")
                print("  - ClientKey: \(connection.clientkey ?? "nil")")
                print("  - Connected Date: \(connection.connectedDate)")
            }
        } catch {
            print("❌ Failed to load bridge connection: \(error)")
            print("  - Error details: \(error.localizedDescription)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: connectedBridgeKey)
            userDefaults.synchronize()
            isConnectionValidated = false
            print("🧹 Cleaned up corrupted data")
        }
    }
    
    // MARK: - Hue API Response Models
    private struct HueAPIV2Response: Decodable {
        let errors: [HueAPIV2Error]
        let data: [HueAPIV2Data]
    }
    
    private struct HueAPIV2Error: Decodable {
        let description: String
    }
    
    private struct HueAPIV2Data: Decodable {
        // The data array can contain various resource types
        // For validation purposes, we just need to know if data is present
    }
    
    var isConnected: Bool {
        connectedBridge != nil
    }
    
    /// Validate that the current connection is alive/reachable.
    /// Broadcasts the result via connectionValidationPublisher.
    func validateConnection() async {
        guard let bridge = currentConnectedBridge?.bridge else {
            print("❌ validateConnection: No connected bridge available")
            isConnectionValidated = false
            connectionValidationSubject.send(.failure(message: "No bridge connection available"))
            return
        }
        isConnectionValidated = false
        
        let urlString = "https://\(bridge.internalipaddress)/clip/v2/resource"

        let delegate = InsecureURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: urlString) else {
            print("❌ validateConnection: Invalid URL: \(urlString)")
            let errorMessage = "Invalid bridge URL"
            connectionValidationSubject.send(.failure(message: errorMessage))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentConnectedBridge?.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print(request)
        
        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("🌐 validateConnection: HTTP \(http.statusCode)")
            }

            // Attempt to decode Hue API v2 response which has the structure:
            // {"errors": [], "data": []}
            do {
                let response = try JSONDecoder().decode(HueAPIV2Response.self, from: data)
                
                // Check for errors first
                if !response.errors.isEmpty {
                    let errorMessages = response.errors.map { $0.description }.joined(separator: ", ")
                    print("❌ validateConnection: Hue API v2 errors: \(errorMessages)")
                    self.isConnectionValidated = false
                    // Publish alert to the UI
                    self.alertMessage = errorMessages
                    self.showAlert = true
                    // Broadcast failure event
                    connectionValidationSubject.send(.failure(message: errorMessages))
                    return
                }
                
                // If no errors and we have data, connection is valid
                if response.errors.isEmpty {
                    print("✅ validateConnection: Success - connection validated with \(response.data.count) data items")
                    self.isConnectionValidated = true
                    // Broadcast success event
                    connectionValidationSubject.send(.success)
                } else {
                    print("ℹ️ validateConnection: No errors but unexpected response structure")
                    self.isConnectionValidated = false
                    let errorMessage = "Unexpected response from bridge"
                    connectionValidationSubject.send(.failure(message: errorMessage))
                }
            } catch {
                // If decoding into the Hue v2 format fails, log raw string for diagnostics
                if let responseString = String(data: data, encoding: .utf8) {
                    print("ℹ️ validateConnection: Failed to decode v2 response: \(responseString)")
                } else {
                    print("ℹ️ validateConnection: Received non-UTF8 data (\(data.count) bytes)")
                }
                self.isConnectionValidated = false
                let errorMessage = "Invalid response from bridge"
                connectionValidationSubject.send(.failure(message: errorMessage))
            }
        } catch {
            print("❌ validateConnection: Network error: \(error.localizedDescription)")
            self.isConnectionValidated = false
            self.alertMessage = error.localizedDescription
            self.showAlert = true
            // Broadcast failure event
            connectionValidationSubject.send(.failure(message: error.localizedDescription))
        }
    }
        
}
