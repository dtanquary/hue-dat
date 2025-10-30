//
//  BridgeModels.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import Foundation

// MARK: - Bridge Info
struct BridgeInfo: Codable, Identifiable {
    let id: String
    let internalipaddress: String
    let port: Int
    let serviceName: String?
    
    var displayAddress: String {
        return "\(internalipaddress):\(port)"
    }
    
    var shortId: String {
        return String(id.prefix(8)) + "..."
    }
    
    var displayName: String {
        return serviceName ?? shortId
    }
}

// MARK: - Bridge Connection Info
struct BridgeConnectionInfo: Codable {
    let bridge: BridgeInfo
    let username: String
    let clientkey: String?
    let connectedDate: Date
    
    init(bridge: BridgeInfo, registrationResponse: BridgeRegistrationResponse) {
        self.bridge = bridge
        self.username = registrationResponse.username
        self.clientkey = registrationResponse.clientkey
        self.connectedDate = Date()
    }
}

// MARK: - Bridge Registration Response
struct BridgeRegistrationResponse: Codable {
    let username: String
    let clientkey: String?
}

// MARK: - Hue Bridge Error
struct HueBridgeError: Codable {
    let type: Int
    let address: String
    let description: String
}

struct HueBridgeErrorResponse: Codable {
    let error: HueBridgeError
}

// MARK: - Bridge Registration Error
enum BridgeRegistrationError: Error, LocalizedError {
    case linkButtonNotPressed(String)
    case bridgeError(String)
    case networkError(Error)
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .linkButtonNotPressed(let description):
            return description
        case .bridgeError(let description):
            return description
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}