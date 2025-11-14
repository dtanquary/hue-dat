//
//  BridgeDiscoveryService.swift
//  HueDatShared
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Network
import Foundation
import Combine

// MARK: - Bridge Discovery Service
@MainActor
public class BridgeDiscoveryService: ObservableObject {
    @Published public var isLoading = false
    @Published public var discoveredBridges: [BridgeInfo] = []
    @Published public var error: Error?
    @Published public var isRegistering = false
    @Published public var registrationSuccess = false
    @Published public var showNoBridgesAlert = false

    // Store reference to active browser for manual cancellation
    private var activeBrowser: NWBrowser?

    public init() {}

    public func discoverBridges() async {
        // Ensure we're on the main actor for all state updates
        await MainActor.run {
            isLoading = true
            error = nil
            showNoBridgesAlert = false
        }

        var bridges: [BridgeInfo] = []

        /*
        // Try mDNS discovery first (works on local network)
        do {
            bridges = try await performHueBridgeDiscoveryWithMDNS()
            print("Loaded bridges via mDNS")
        } catch {
            print("mDNS discovery failed: \(error.localizedDescription), falling back to discovery endpoint")
            bridges = [] // Ensure bridges is empty to trigger fallback
        }
         */

        // If no bridges found via mDNS (either empty result or failure), fallback to discovery endpoint
        if bridges.isEmpty {
            do {
                let fallbackBridges = try await performHueBridgeDiscoveryWithDiscoveryEndpoint()
                await MainActor.run {
                    discoveredBridges = fallbackBridges
                }
                print("Loaded bridges via Discovery endpoint fallback")
            } catch {
                await MainActor.run {
                    self.error = error
                }
                print("Failed to load bridges via both methods: \(error.localizedDescription)")
            }
        } else {
            await MainActor.run {
                discoveredBridges = bridges
            }
        }

        // Show alert if no bridges found at all
        await MainActor.run {
            if discoveredBridges.isEmpty && error == nil {
                showNoBridgesAlert = true
            }
            isLoading = false
        }
    }

    public func cancelDiscovery() {
        print("🛑 Manually cancelling bridge discovery")
        activeBrowser?.cancel()
        activeBrowser = nil
        Task { @MainActor in
            isLoading = false
        }
    }

    private func performHueBridgeDiscoveryWithDiscoveryEndpoint() async throws -> [BridgeInfo] {
        let cacheKey = "hue_bridge_discovery_cache"
        let cacheTimestampKey = "hue_bridge_discovery_timestamp"
        let cacheExpirationInterval: TimeInterval = 15 * 60 // 15 minutes in seconds

        // Check if we have cached data and if it's still valid
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cacheTimestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date {

            let cacheAge = Date().timeIntervalSince(cacheTimestamp)

            if cacheAge < cacheExpirationInterval {
                print("📦 Using cached bridge discovery data (age: \(Int(cacheAge/60)) minutes)")
                do {
                    let cachedBridges = try JSONDecoder().decode([BridgeInfo].self, from: cachedData)
                    return cachedBridges
                } catch {
                    print("⚠️ Failed to decode cached bridge data, fetching fresh data: \(error)")
                    // Continue to fetch fresh data if cache is corrupted
                }
            } else {
                print("🕐 Cache expired (age: \(Int(cacheAge/60)) minutes), fetching fresh data")
            }
        } else {
            print("📭 No cache found, fetching fresh data")
        }

        // Fetch fresh data from the API
        print("🌐 Fetching bridge discovery data from API")
        let url = URL(string: "https://discovery.meethue.com")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let bridges = try JSONDecoder().decode([BridgeInfo].self, from: data)

        // Cache the fresh data
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        print("💾 Cached fresh bridge discovery data")

        return bridges

        /*
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
         */
    }

    private func performHueBridgeDiscoveryWithMDNS() async throws -> [BridgeInfo] {
        print("🔍 Starting mDNS discovery for _hue._tcp services...")

        return try await withCheckedThrowingContinuation { continuation in
            var discoveredBridges: [BridgeInfo] = []
            var hasResumed = false
            var debounceTimer: DispatchWorkItem?

            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi // Prefer WiFi for local network discovery
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: .any) // Force IPv4

            let browser = NWBrowser(for: .bonjour(type: "_hue._tcp", domain: "local."), using: parameters)

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
                    print("⏱️ Debounce completed - found \(discoveredBridges.count) bridge(s)")
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

                        let connection = NWConnection(to: endpoint, using: parameters)

                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                print("🔍 Raw connection ready state: \(state)")

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
                                        // Handle IPv6 addresses properly, removing zone identifier if present
                                        let ipv6String = ipv6.debugDescription
                                        // Remove zone identifier (e.g., %en0) from link-local addresses
                                        if let percentIndex = ipv6String.firstIndex(of: "%") {
                                            ipAddress = String(ipv6String[..<percentIndex])
                                        } else {
                                            ipAddress = ipv6String
                                        }
                                        print("   📍 Processed IPv6 address: \(ipv6String) -> \(ipAddress ?? "nil")")
                                    default:
                                        print("   ⚠️ Unsupported host type for \(name)")
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
                                    } else {
                                        print("   ⚠️ Failed to extract IP address or bridge ID for \(name)")
                                    }
                                } else {
                                    print("   ⚠️ No remote endpoint available for \(name)")
                                }
                                connection.cancel()
                            case .failed(let error):
                                print("   ❌ Connection failed for service: \(name) - \(error)")
                                connection.cancel()
                            case .cancelled:
                                print("   ⏹️ Connection cancelled for service: \(name)")
                            case .waiting(let error):
                                print("   ⏳ Connection waiting for service: \(name) - \(error)")
                            case .preparing:
                                print("   🔄 Connection preparing for service: \(name)")
                            case .setup:
                                print("   ⚙️ Connection setup for service: \(name)")
                            @unknown default:
                                print("   ❓ Unknown connection state for service: \(name) - \(state)")
                            }
                        }

                        // Add error handling for connection start
                        do {
                            connection.start(queue: .main)
                        } catch {
                            print("   ❌ Failed to start connection for service: \(name) - \(error)")
                            connection.cancel()
                        }

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
                    print("⏰ 10-second fallback timeout reached, but mDNS browser already cancelled...")
                }
            }
        }
    }
}
