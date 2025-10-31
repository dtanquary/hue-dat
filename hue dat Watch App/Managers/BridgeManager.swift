//
//  BridgeManager.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Bridge Manager
@MainActor
class BridgeManager: ObservableObject {
    @Published var connectedBridge: BridgeConnectionInfo?
    
    private let userDefaults = UserDefaults.standard
    private let connectedBridgeKey = "ConnectedBridge"
    
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
                print("  - Bridge: \(connection.bridge.displayName) (\(connection.bridge.shortId))")
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
            print("🧹 Cleaned up corrupted data")
        }
    }
    
    var isConnected: Bool {
        connectedBridge != nil
    }
}
