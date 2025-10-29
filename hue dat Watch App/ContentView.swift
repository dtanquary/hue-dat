//
//  ContentView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine
import Network
import UIKit

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

// MARK: - Bridge Discovery Service
@MainActor
class BridgeDiscoveryService: ObservableObject {
    @Published var isLoading = false
    @Published var discoveredBridges: [BridgeInfo] = []
    @Published var error: Error?
    @Published var isRegistering = false
    @Published var registrationSuccess = false
    @Published var showNoBridgesAlert = false
    
    // Store reference to active browser for manual cancellation
    private var activeBrowser: NWBrowser?
    
    func discoverBridges() async {
        isLoading = true
        error = nil
        showNoBridgesAlert = false
        
        do {
            // Try mDNS discovery first (works on local network)
            let bridges = try await performHueBridgeDiscoveryWithMDNS()
            
            // If no bridges found via mDNS, fallback to discovery endpoint
            if bridges.isEmpty {
                let fallbackBridges = try await performHueBridgeDiscoveryWithDiscoveryEndpoint()
                discoveredBridges = fallbackBridges
                print("Loaded bridges via Discovery endpoint fallback")
            } else {
                print("Loaded bridges via mDNS")
                discoveredBridges = bridges
            }
            
            // Show alert if no bridges found at all
            if discoveredBridges.isEmpty {
                showNoBridgesAlert = true
            }
        } catch {
            self.error = error
            print("Failed to load any bridges")
        }
        
        isLoading = false
    }
    
    func cancelDiscovery() {
        print("🛑 Manually cancelling bridge discovery")
        activeBrowser?.cancel()
        activeBrowser = nil
        isLoading = false
    }
    
    func registerWithBridge(_ bridge: BridgeInfo) async {
        isRegistering = true
        error = nil
        registrationSuccess = false
        
        do {
            let registrationResult = try await performBridgeRegistration(bridge: bridge)
            print("Registration successful: \(registrationResult)")
            registrationSuccess = true
        } catch {
            self.error = error
        }
        
        isRegistering = false
    }
    
    private func performHueBridgeDiscoveryWithDiscoveryEndpoint() async throws -> [BridgeInfo] {
        // For production, uncomment the network call:
        /*
        let url = URL(string: "https://discovery.meethue.com")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([BridgeInfo].self, from: data)
        */
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Mocked payload for development
        let json = """
        [
            {"id":"001788fffe4ffdfb","internalipaddress":"192.168.1.124","port":443,"serviceName":null},
            {"id":"001788fffe123456","internalipaddress":"192.168.1.125","port":443,"serviceName":null}
        ]
        """.data(using: .utf8)!
        
        return try JSONDecoder().decode([BridgeInfo].self, from: json)
    }
    
    private func performHueBridgeDiscoveryWithMDNS() async throws -> [BridgeInfo] {
        print("🔍 Starting mDNS discovery for _hue._tcp services...")
        
        return try await withCheckedThrowingContinuation { continuation in
            var discoveredBridges: [BridgeInfo] = []
            var hasResumed = false
            var debounceTimer: DispatchWorkItem?
            let browser = NWBrowser(for: .bonjour(type: "_hue._tcp", domain: "local."), using: .tcp)
            
            // Store reference for manual cancellation
            activeBrowser = browser
            
            func resumeOnce(with result: Result<[BridgeInfo], Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                debounceTimer?.cancel() // Cancel any pending timer
                
                // Clear reference on main actor
                Task { @MainActor in
                    activeBrowser = nil
                }
                
                switch result {
                case .success(let bridges):
                    print("✅ mDNS discovery completed with \(bridges.count) bridge(s)")
                    continuation.resume(returning: bridges)
                case .failure(let error):
                    print("❌ mDNS discovery failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            // Function to handle debounced completion when bridges are found
            func scheduleCompletion() {
                guard !discoveredBridges.isEmpty else { return }
                
                // Cancel any existing timer
                debounceTimer?.cancel()
                
                // Create new debounced timer (1 second after last bridge added)
                debounceTimer = DispatchWorkItem {
                    print("⏱️ Debounce completed - found \(discoveredBridges.count) bridge(s), stopping discovery")
                    browser.cancel()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: debounceTimer!)
            }
            
            browser.stateUpdateHandler = { state in
                print("📡 mDNS browser state changed to: \(state)")
                switch state {
                case .failed(let error):
                    print("❌ mDNS browser failed: \(error)")
                    resumeOnce(with: .failure(error))
                case .cancelled:
                    print("⏹️ mDNS browser cancelled")
                    resumeOnce(with: .success(discoveredBridges))
                case .ready:
                    print("🟢 mDNS browser ready")
                case .setup:
                    print("⚙️ mDNS browser setting up")
                case .waiting(let error):
                    print("⏳ mDNS browser waiting: \(error)")
                @unknown default:
                    print("❓ mDNS browser unknown state: \(state)")
                }
            }
            
            browser.browseResultsChangedHandler = { results, changes in
                print("📋 mDNS results changed - Total results: \(results.count)")
                
                for change in changes {
                    switch change {
                    case .added(let result):
                        print("➕ Added service: \(result)")
                    case .removed(let result):
                        print("➖ Removed service: \(result)")
                    case .identical:
                        print("🔄 Service identical")
                    @unknown default:
                        print("❓ Unknown change: \(change)")
                    }
                }
                
                for result in results {
                    print("🔍 Processing result: \(result)")
                    print("   - Endpoint: \(result.endpoint)")
                    
                    switch result.endpoint {
                    case .service(let name, let type, let domain, let interface):
                        print("   - Service name: '\(name)'")
                        print("   - Service type: '\(type)'")
                        print("   - Service domain: '\(domain)'")
                        print("   - Interface: \(String(describing: interface))")
                        
                        // Try to extract bridge ID from TXT record metadata
                        var bridgeId: String?
                        
                        let endpoint = NWEndpoint.service(
                            name: name,
                            type: "_hue._tcp",
                            domain: "local.",
                            interface: nil
                        )
                        
                        // Create a connection to get TXT record data
                        let host = NWEndpoint.Host("\"\(name)\" \(type) \(domain)")
                        
                        print("Connecting to endpoint: \(endpoint)")
                        
                        let connection = NWConnection(to: endpoint, using: .tcp)
                        
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                // For now, generate a bridge ID from the service name
                                // In a real implementation, you'd want to query the bridge's API
                                // to get the actual bridge ID
                                bridgeId = "001788fffe\(String(name.hashValue).suffix(6))"
                                
                                if let endpoint = connection.currentPath?.remoteEndpoint,
                                   case .hostPort(let host, _) = endpoint {
                                    var ipAddress: String?
                                    
                                    switch host {
                                    case .ipv4(let ipv4):
                                        ipAddress = ipv4.rawValue.withUnsafeBytes { bytes in
                                            let addr = bytes.bindMemory(to: UInt8.self)
                                            return "\(addr[0]).\(addr[1]).\(addr[2]).\(addr[3])"
                                        }
                                    case .ipv6(let ipv6):
                                        ipAddress = ipv6.debugDescription
                                    default:
                                        break
                                    }
                                    
                                    if let ip = ipAddress, let id = bridgeId {
                                        print("   📍 Resolved IP: \(ip) for bridge ID: \(id)")
                                        let bridgeInfo = BridgeInfo(
                                            id: id,
                                            internalipaddress: ip,
                                            port: 443,
                                            serviceName: name
                                        )
                                        
                                        // Avoid duplicates
                                        if !discoveredBridges.contains(where: { $0.id == bridgeInfo.id }) {
                                            discoveredBridges.append(bridgeInfo)
                                            print("   ➕ Added bridge to results: \(bridgeInfo)")
                                            
                                            // Schedule completion with debouncing
                                            scheduleCompletion()
                                        } else {
                                            print("   🔁 Bridge already in results (duplicate)")
                                        }
                                    }
                                }
                                connection.cancel()
                            case .failed:
                                print("   ❌ Connection failed for service: \(name)")
                                connection.cancel()
                            default:
                                break
                            }
                        }
                        
                        connection.start(queue: .main)
                        
                    case .hostPort(let host, let port):
                        print("   - Host/Port endpoint: \(host):\(port)")
                    case .unix(let path):
                        print("   - Unix socket: \(path)")
                    case .url(let url):
                        print("   - URL endpoint: \(url)")
                    @unknown default:
                        print("   - Unknown endpoint type: \(result.endpoint)")
                    }
                }
            }
            
            // Start browsing
            print("🚀 Starting mDNS browser...")
            browser.start(queue: .main)
            
            // Fallback timeout - stop browsing after 10 seconds if no bridges found
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if discoveredBridges.count == 0 && browser.state != .cancelled {
                    print("⏰ 10-second fallback timeout reached, cancelling mDNS browser...")
                    browser.cancel()
                    // The cancellation will trigger the state handler which will resume
                } else {
                    print("⏰ 10-second fallback timeout reached,but mDNS browser already cancelled...")
                }
            }
        }
    }
    
    private func performBridgeRegistration(bridge: BridgeInfo) async throws -> BridgeRegistrationResponse {
        // For production, uncomment the network call:
        /*
        let url = URL(string: "https://\(bridge.displayAddress)/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "devicetype": "hue_dat_watch_app#\(UIDevice.current.name)",
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
        
        // Mock successful registration response
        return BridgeRegistrationResponse(
            username: "mock-username-\(UUID().uuidString.prefix(8))",
            clientkey: "mock-client-key-\(UUID().uuidString.prefix(16))"
        )
    }
}



// MARK: - Bridge Registration Service
@MainActor
class BridgeRegistrationService: ObservableObject {
    @Published var error: Error?
    @Published var registeringBridge: BridgeInfo?
    @Published var successfulBridge: BridgeInfo?
    @Published var registrationResponse: BridgeRegistrationResponse?
    @Published var showLinkButtonAlert = false
    @Published var linkButtonBridge: BridgeInfo?
    
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
            "devicetype": "hue_dat_watch_app#\(UIDevice.current.name)",
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
    private var linkButtonAttempts: Set<String> = []
    
    private func hasAttemptedLinkButton(for bridge: BridgeInfo) -> Bool {
        return linkButtonAttempts.contains(bridge.id)
    }
    
    private func markLinkButtonAttempt(for bridge: BridgeInfo) {
        linkButtonAttempts.insert(bridge.id)
    }
}

struct ContentView: View {
    @StateObject private var discoveryService = BridgeDiscoveryService()
    @StateObject private var bridgeManager = BridgeManager()
    @State private var showBridgesList = false
    @State private var showDisconnectAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Hue Bridge Discovery")
                        
                        Text("Hue Control")
                            .font(.title3.weight(.medium))
                    }
                    
                    // Main content
                    if let connectedBridge = bridgeManager.connectedBridge {
                        // Connected state
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Text(connectedBridge.bridge.displayName)
                                    .font(.headline)
                                
                                Text(connectedBridge.bridge.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("Connected \(connectedBridge.connectedDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                            
                            Button("Disconnect", role: .destructive) {
                                showDisconnectAlert = true
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Disconnect from current bridge")
                        }
                    } else {
                        // Discovery state
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await discoveryService.discoverBridges()
                                    if !discoveryService.discoveredBridges.isEmpty {
                                        showBridgesList = true
                                    }
                                }
                            } label: {
                                HStack {
                                    if discoveryService.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    Text(discoveryService.isLoading ? "Searching..." : "Find Bridges")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .buttonStyle(.glass)
                            .disabled(discoveryService.isLoading)
                            .accessibilityLabel("Discover Hue bridges on network")
                            
                            // Tappable bridge count
                            if !discoveryService.discoveredBridges.isEmpty && !discoveryService.isLoading {
                                Button {
                                    showBridgesList = true
                                } label: {
                                    Text("\(discoveryService.discoveredBridges.count) found")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show \(discoveryService.discoveredBridges.count) discovered bridge\(discoveryService.discoveredBridges.count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Hue Control")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showBridgesList, onDismiss: {
            // Cancel any ongoing discovery when sheet is dismissed
            if discoveryService.isLoading {
                discoveryService.cancelDiscovery()
            }
        }) {
            BridgesListView(bridges: discoveryService.discoveredBridges, bridgeManager: bridgeManager)
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
            }
        } message: {
            Text("Are you sure you want to disconnect? You'll need to set up the connection again.")
        }
        .alert("Discovery Error", isPresented: .constant(discoveryService.error != nil)) {
            Button("OK") {
                discoveryService.error = nil
            }
        } message: {
            if let error = discoveryService.error {
                Text("Failed to discover bridges: \(error.localizedDescription)")
            }
        }
        .alert("No Bridges Found", isPresented: $discoveryService.showNoBridgesAlert) {
            Button("OK") { }
        } message: {
            Text("No Hue bridges could be found on your network. Make sure your bridge is connected and try again.")
        }
    }
}

struct BridgesListView: View {
    let bridges: [BridgeInfo]
    let bridgeManager: BridgeManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registrationService = BridgeRegistrationService()
    
    var body: some View {
        NavigationStack {
            List(bridges) { bridge in
                Button {
                    Task {
                        await registrationService.registerWithBridge(bridge)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bridge.displayName)
                                .font(.headline)
                                .accessibilityLabel("Bridge: \(bridge.displayName)")
                            
                            Text(bridge.displayAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("IP address: \(bridge.displayAddress)")
                        }
                        
                        Spacer()
                        
                        if registrationService.isRegistering(bridge: bridge) {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if registrationService.isRegistered(bridge: bridge) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.quaternary)
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(registrationService.hasActiveRegistration && !registrationService.isRegistering(bridge: bridge))
                .accessibilityLabel("Register with bridge \(bridge.displayName)")
            }
            .navigationTitle("Bridges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(registrationService.hasActiveRegistration)
                }
            }
        }
        .alert("Error", isPresented: .constant(registrationService.error != nil)) {
            Button("OK") {
                registrationService.error = nil
            }
        } message: {
            if let error = registrationService.error {
                Text(error.localizedDescription)
            }
        }
        .alert("Success", isPresented: .constant(registrationService.successfulBridge != nil)) {
            Button("OK") {
                if let bridge = registrationService.successfulBridge,
                   let response = registrationService.registrationResponse {
                    bridgeManager.saveConnection(bridge: bridge, registrationResponse: response)
                }
                registrationService.clearSuccess()
                dismiss()
            }
        } message: {
            if let bridge = registrationService.successfulBridge {
                Text("Connected to \(bridge.displayName)")
            }
        }
        .alert("Press Link Button", isPresented: $registrationService.showLinkButtonAlert) {
            Button("Done") {
                if let bridge = registrationService.linkButtonBridge {
                    Task {
                        await registrationService.registerWithBridge(bridge)
                    }
                }
                registrationService.clearLinkButtonAlert()
            }
            Button("Cancel") {
                registrationService.clearLinkButtonAlert()
            }
        } message: {
            Text("Press the link button on your bridge, then tap Done.")
        }
    }
}

#Preview {
    ContentView()
}
