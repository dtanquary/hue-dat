//
//  BridgesListView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine

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