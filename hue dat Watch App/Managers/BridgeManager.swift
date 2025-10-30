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
            connectedBridge = connectionInfo
            print("Bridge connection saved: \(bridge.shortId)")
        } catch {
            print("Failed to save bridge connection: \(error)")
        }
    }
    
    func disconnectBridge() {
        userDefaults.removeObject(forKey: connectedBridgeKey)
        connectedBridge = nil
        print("Bridge disconnected and cleared from storage")
    }
    
    private func loadConnectedBridge() {
        guard let data = userDefaults.data(forKey: connectedBridgeKey) else {
            print("No saved bridge connection found")
            return
        }
        
        do {
            connectedBridge = try JSONDecoder().decode(BridgeConnectionInfo.self, from: data)
            print("Loaded saved bridge connection: \(connectedBridge?.bridge.shortId ?? "unknown")")
        } catch {
            print("Failed to load bridge connection: \(error)")
            // Clean up corrupted data
            userDefaults.removeObject(forKey: connectedBridgeKey)
        }
    }
    
    var isConnected: Bool {
        connectedBridge != nil
    }
}
