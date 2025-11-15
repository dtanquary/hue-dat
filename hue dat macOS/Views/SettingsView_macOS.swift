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

    @EnvironmentObject var bridgeManager: BridgeManager

    @State private var showDisconnectAlert = false

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
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                // Invisible spacer to center title
                Button("") { }
                    .buttonStyle(.plain)
                    .opacity(0)
                    .disabled(true)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
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
                            .cornerRadius(8)

                            // Disconnect button
                            Button(action: {
                                showDisconnectAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "link.badge.minus")
                                    Text("Disconnect Bridge")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bridge Connection")
                                .font(.headline)

                            Text("No bridge connected")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
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
    }

    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView_macOS(onBack: {})
        .environmentObject(BridgeManager())
}
