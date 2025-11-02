//
//  SettingsView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 11/2/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var bridgeManager: BridgeManager
    @State private var showDisconnectAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Bridge Connection Section
                Section("Bridge Connection") {
                    if let bridge = bridgeManager.connectedBridge {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("IP Address")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.bridge.internalipaddress)
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Bridge ID")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(bridge.bridge.id.prefix(8)))
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Connected")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bridge.connectedDate, style: .date)
                                    .font(.caption)
                            }
                        }
                        .font(.caption)

                        Button(role: .destructive) {
                            showDisconnectAlert = true
                        } label: {
                            Label("Disconnect Bridge", systemImage: "xmark.circle")
                        }
                    } else {
                        Text("No bridge connected")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
