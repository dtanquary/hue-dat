//
//  SettingsView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 11/2/25.
//

import SwiftUI
import HueDatShared

struct SettingsView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var showDisconnectAlert = false
    @Environment(\.dismiss) private var dismiss

    // Dynamic Type scaled metrics
    @ScaledMetric(relativeTo: .caption) private var infoSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var labelIconSpacing: CGFloat = 6

    var body: some View {
        NavigationStack {
            List {
                // Bridge Connection Section
                Section("Bridge Connection") {
                    if let bridge = bridgeManager.connectedBridge {
                        VStack(alignment: .leading, spacing: infoSpacing) {
                            Text("Server Side Events")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                   
                            HStack {
                                /*
                                Circle()
                                    .fill(bridgeManager.isSSEConnected ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                 */
                                Image(systemName: bridgeManager.isSSEConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                    .font(.title3)
                                    .foregroundStyle(bridgeManager.isSSEConnected ? Color.green : Color.red)
                                Text(bridgeManager.isSSEConnected ? "Connected" : "Disconnected")
                                    .font(.caption.monospaced())
                                    .padding(.leading, 2)
                            }

                            // Show reconnect button only when disconnected
                            if !bridgeManager.isSSEConnected {
                                Button {
                                    Task {
                                        do {
                                            try await HueAPIService.shared.startEventStream()
                                            print("✅ SSE stream reconnected via settings button")
                                        } catch {
                                            print("❌ Failed to reconnect SSE stream: \(error)")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: labelIconSpacing) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                        Text("Reconnect")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                            
                            Divider()
                            
                            Text("IP Address")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(bridge.bridge.internalipaddress)
                                .font(.caption.monospaced())
                            
                            Divider()
                            
                            Text("Bridge ID")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(bridge.bridge.id))
                                .font(.caption.monospaced())
                            
                            Divider()
                            
                            Text("Connected")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(bridge.connectedDate, style: .date)
                                .font(.caption)
                                .padding(.bottom, 8)
                            
                            /*
                            HStack {
                                Text("IP Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.bridge.internalipaddress)
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Bridge ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(bridge.bridge.id.prefix(8)))
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.connectedDate, style: .date)
                                    .font(.caption)
                            }
                             */
                        }
                        
                        Button(role: .destructive) {
                            showDisconnectAlert = true
                        } label: {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "xmark.circle")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Disconnect Bridge")
                                    .font(.body)
                            }
                        }
                    } else {
                        Text("No bridge connected")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
                // Demo Mode Section
                Section {
                    if bridgeManager.isDemoMode {
                        // Demo mode active - show status and disable button
                        VStack(alignment: .leading, spacing: infoSpacing) {
                            HStack {
                                Image(systemName: "eyes")
                                    .foregroundStyle(.blue)
                                Text("Demo Mode Active")
                                    .font(.body)
                                    .foregroundStyle(.blue)
                            }
                            Text("Demo mode allows you to explore the app interface without a network connection.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            bridgeManager.disableDemoMode()
                            // Re-validate connection after disabling demo mode
                            Task {
                                await bridgeManager.validateConnection()
                            }
                        } label: {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "wifi")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Disable Demo Mode")
                                    .font(.body)
                            }
                        }
                    } else {
                        // Demo mode not active - show toggle to enable
                        Toggle(isOn: Binding(
                            get: { bridgeManager.isDemoMode },
                            set: { newValue in
                                if newValue {
                                    bridgeManager.enableDemoMode()
                                } else {
                                    bridgeManager.disableDemoMode()
                                }
                            }
                        )) {
                            HStack(spacing: labelIconSpacing) {
                                Image(systemName: "eyes")
                                    .font(.body)
                                    .frame(minWidth: labelIconSpacing * 3, alignment: .leading)
                                Text("Demo Mode")
                                    .font(.body)
                            }
                        }
                    }
                } header: {
                    Text("Demo Mode")
                } footer: {
                    if !bridgeManager.isDemoMode {
                        Text("Enable demo mode to explore the app without a network connection.")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    bridgeManager.disconnectBridge()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to disconnect? You'll need to set up the connection again.")
            }
        }
    }

}
