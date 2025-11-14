//
//  BridgesListView.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/29/25.
//

import SwiftUI
import Combine
import HueDatShared

struct BridgesListView: View {
    let bridges: [BridgeInfo]
    let bridgeManager: BridgeManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registrationService = BridgeRegistrationService(deviceIdentifierProvider: WatchOSDeviceIdentifierProvider())
    
    var body: some View {
        NavigationStack {
            bridgesList
                .navigationTitle("Bridges")
                .navigationBarTitleDisplayMode(.automatic)
        }
        .toolbar {
            toolbarContent
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {
                registrationService.error = nil
            }
        } message: {
            if let error = registrationService.error {
                Text(error.localizedDescription)
            }
        }
        .alert("Success", isPresented: successBinding) {
            Button("OK") {
                registrationService.clearSuccess()
                dismiss()
            }
        } message: {
            if let bridge = registrationService.successfulBridge {
                Text("Connected to \(bridge.displayName)")
            }
        }
        .onChange(of: registrationService.successfulBridge) { _, newBridge in
            if let bridge = newBridge,
               let response = registrationService.registrationResponse {
                bridgeManager.saveConnection(bridge: bridge, registrationResponse: response)
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
    
    // MARK: - Subviews
    
    private var bridgesList: some View {
        List(bridges) { bridge in
            bridgeRow(for: bridge)
        }
    }
    
    private func bridgeRow(for bridge: BridgeInfo) -> some View {
        Button {
            Task {
                await registrationService.registerWithBridge(bridge)
            }
        } label: {
            bridgeRowLabel(for: bridge)
        }
        .buttonStyle(.plain)
        .disabled(registrationService.hasActiveRegistration && !registrationService.isRegistering(bridge: bridge))
        .accessibilityLabel("Register with bridge \(bridge.displayName)")
    }
    
    private func bridgeRowLabel(for bridge: BridgeInfo) -> some View {
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
            
            bridgeStatusIcon(for: bridge)
        }
    }
    
    @ViewBuilder
    private func bridgeStatusIcon(for bridge: BridgeInfo) -> some View {
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
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                /*showSettings = true*/
            } label: {
                Image(systemName: "gear")
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                /*
                Task {
                    await refreshData()
                }
                 */
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
            }
        }
    }
    
    // MARK: - Bindings
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { registrationService.error != nil },
            set: { if !$0 { registrationService.error = nil } }
        )
    }
    
    private var successBinding: Binding<Bool> {
        Binding(
            get: { registrationService.successfulBridge != nil },
            set: { _ in }
        )
    }
}
