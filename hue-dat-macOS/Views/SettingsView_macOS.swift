//
//  SettingsView_macOS.swift
//  hue dat macOS
//
//  Settings view for bridge management and app information
//

import SwiftUI
import HueDatShared

struct SettingsView_macOS: View {
    let onBack: () -> Void

    @Environment(BridgeManager.self) var bridgeManager

    @State private var showDisconnectAlert = false
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Back")
                    }
                }
                .buttonStyle(.accessoryBar)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

                Spacer()

                Text("Settings")
                    .font(.headline)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // General Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.headline)

                        VStack(spacing: 8) {
                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .onChange(of: launchAtLogin) { oldValue, newValue in
                                    do {
                                        if newValue {
                                            try LaunchAtLoginManager.shared.enable()
                                        } else {
                                            try LaunchAtLoginManager.shared.disable()
                                        }
                                    } catch {
                                        // Revert toggle if operation failed
                                        launchAtLogin = !newValue
                                    }
                                }
                        }
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Bridge Connection Section
                    if let connection = bridgeManager.connectedBridge {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bridge Connection")
                                .font(.headline)

                            // Bridge details
                            VStack(spacing: 8) {
                                settingRow(label: "Bridge Name", value: connection.bridge.displayName)
                                settingRow(label: "IP Address", value: connection.bridge.displayAddress)
                                settingRow(label: "Bridge ID", value: connection.bridge.id)
                                settingRow(label: "Connected", value: formattedDate(connection.connectedDate))
                            }
                            .padding()
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            // Disconnect button
                            Button(action: {
                                showDisconnectAlert = true
                            }) {
                                HStack {
                                    Text("Disconnect Bridge")
                                        .padding(6)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bridge Connection")
                                .font(.headline)

                            Text("No bridge connected")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {
                showDisconnectAlert = false
            }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
                onBack()
            }
        } message: {
            Text("Are you sure you want to disconnect from this bridge? You'll need to pair again to reconnect.")
        }
        .onAppear {
            // Load current launch at login state
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }
    }

    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    SettingsView_macOS(onBack: {})
        .environment(BridgeManager())
}
