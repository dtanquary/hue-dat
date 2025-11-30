//
//  SettingsView_iOS.swift
//  hue dat iOS
//
//  Settings view for bridge management and app information
//

import SwiftUI
import HueDatShared

struct SettingsView_iOS: View {
    @ObservedObject var bridgeManager: BridgeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDisconnectAlert = false

    var body: some View {
        List {
            // Bridge Connection Section
            if let connection = bridgeManager.connectedBridge {
                Section("Bridge Connection") {
                    settingRow(label: "Bridge Name", value: connection.bridge.displayName)
                    settingRow(label: "IP Address", value: connection.bridge.displayAddress)
                    settingRow(label: "Bridge ID", value: connection.bridge.id)
                    settingRow(label: "Connected", value: formattedDate(connection.connectedDate))

                    // Disconnect button
                    Button(role: .destructive) {
                        showDisconnectAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Disconnect Bridge")
                            Spacer()
                        }
                    }
                }
            } else {
                Section("Bridge Connection") {
                    Text("No bridge connected")
                        .foregroundColor(.secondary)
                }
            }

            // About Section
            Section("About") {
                settingRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                settingRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {
                showDisconnectAlert = false
            }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to disconnect from this bridge? You'll need to pair again to reconnect.")
        }
    }

    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
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
    NavigationStack {
        SettingsView_iOS(bridgeManager: BridgeManager())
    }
}
