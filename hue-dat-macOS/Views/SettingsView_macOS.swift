//
//  SettingsView_macOS.swift
//  hue dat macOS
//
//  Settings view for bridge management and app information
//

import SwiftUI
import HueDatShared

struct SettingsView_macOS: View {
    @Environment(BridgeManager.self) var bridgeManager

    @State private var showDisconnectAlert = false
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
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

            Section("Bridge Connection") {
                if let connection = bridgeManager.connectedBridge {
                    Group {
                        LabeledContent("Bridge Name", value: connection.bridge.displayName)
                        LabeledContent("IP Address", value: connection.bridge.displayAddress)
                        LabeledContent("Bridge ID", value: connection.bridge.id)
                        LabeledContent("Connected", value: formattedDate(connection.connectedDate))
                    }
                    .textSelection(.enabled)

                    Button("Disconnect Bridge", role: .destructive) {
                        showDisconnectAlert = true
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("No bridge connected")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            PanelHeader(title: "Settings", showsBack: true)
        }
        .alert("Disconnect Bridge", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {
                showDisconnectAlert = false
            }
            Button("Disconnect", role: .destructive) {
                bridgeManager.disconnectBridge()
            }
        } message: {
            Text("Are you sure you want to disconnect from this bridge? You'll need to pair again to reconnect.")
        }
        .onAppear {
            // Load current launch at login state
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        SettingsView_macOS()
    }
    .environment(BridgeManager())
}
