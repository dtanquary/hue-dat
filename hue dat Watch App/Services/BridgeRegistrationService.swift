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
        // For production, uncomment the network call:
        
        print("performBridgeRegistration called")
        print(bridge)

        let testSuffix = "test1"
        let urlString = "https://\(bridge.internalipaddress)/api"
        let requestBody: [String: Any] = [
            "devicetype": "hue_dat_watch_app#\(testSuffix)",
            "generateclientkey": true
        ]
        
        // Usage
        let client = APIClient()
        client.makePostRequest(url: urlString, body: requestBody) { result in
            switch result {
            case .success(let data):
                // Parse response
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    print("Response: \(json)")
                }
            case .failure(let error):
                print("Error: \(error)")
            }
        }
        
        /*
        let urlString = "https://\(bridge.internalipaddress)/api"
        guard let url = URL(string: urlString) else {
            throw BridgeRegistrationError.bridgeError("Invalid bridge URL: \(bridge.internalipaddress)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "devicetype": "hue_dat_watch_app#\(testSuffix)",
            "generateclientkey": true
        ]
        
        print(requestBody)
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Create a custom URLSession that bypasses SSL verification
        let session = URLSession(configuration: .default, delegate: SSLBypassDelegate(), delegateQueue: nil)
        
        let (data, response) = try await session.data(for: request)
        
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
    
    // Helper method to detect IPv6 addresses
    private func isIPv6Address(_ ipAddress: String) -> Bool {
        // IPv6 addresses contain colons and are not IPv4 format
        return ipAddress.contains(":") && !ipAddress.contains(".")
    }
}

// MARK: - SSL Bypass Delegate
private class SSLBypassDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Bypass SSL verification for local Hue bridge connections
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }
}

// MARK: - Secure URL Session Delegate
class SecureURLSessionDelegate: NSObject, URLSessionDelegate {
    
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Load your root CA certificate
        guard let certPath = Bundle.main.path(forResource: "your-root-ca", ofType: "cer"),
              let certData = try? Data(contentsOf: URL(fileURLWithPath: certPath)),
              let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let status = SecTrustSetAnchorCertificates(serverTrust, [certificate] as CFArray)
        guard status == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        SecTrustSetAnchorCertificatesOnly(serverTrust, false)
        
        if evaluateTrust(serverTrust) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func evaluateTrust(_ trust: SecTrust) -> Bool {
        var trustResult: SecTrustResultType = .invalid
        let status = SecTrustEvaluate(trust, &trustResult)
        guard status == errSecSuccess else { return false }
        return trustResult == .unspecified || trustResult == .proceed
    }
}

// MARK: - Making the POST Request

class APIClient {
    let session: URLSession
    
    init() {
        let delegate = SecureURLSessionDelegate()
        self.session = URLSession(configuration: .default,
                                 delegate: delegate,
                                 delegateQueue: nil)
    }
    
    func makePostRequest(url: String, body: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert to JSON data
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the request
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            completion(.success(data))
        }
        
        task.resume()
    }
}
