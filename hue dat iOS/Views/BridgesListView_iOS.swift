//
//  BridgesListView_iOS.swift
//  hue dat iOS
//
//  List of discovered bridges for registration
//

import SwiftUI
import Combine
import HueDatShared

struct BridgesListView_iOS: View {
    let bridges: [BridgeInfo]
    let bridgeManager: BridgeManager
    var onManualEntryTapped: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registrationService = BridgeRegistrationService(deviceIdentifierProvider: IOSDeviceIdentifierProvider())

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(bridges) { bridge in
                        bridgeRow(for: bridge)
                    }
                }

//                if onManualEntryTapped != nil {
//                    Section {
//                        Button {
//                            onManualEntryTapped?()
//                            dismiss()
//                        } label: {
//                            HStack {
//                                Image(systemName: "plus.circle.fill")
//                                    .font(.title2)
//                                    .foregroundStyle(.blue)
//                                Text("Manually Add Bridge")
//                                    .font(.headline)
//                            }
//                            .frame(maxWidth: .infinity)
//                            .padding(.vertical, 8)
//                        }
//                    }
//                }
            }
            .navigationTitle("Bridges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
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

    private func bridgeRow(for bridge: BridgeInfo) -> some View {
        Button {
            Task {
                await registrationService.registerWithBridge(bridge)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bridge.displayName)
                        .font(.headline)

                    Text(bridge.displayAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                bridgeStatusIcon(for: bridge)
            }
        }
        .disabled(registrationService.hasActiveRegistration && !registrationService.isRegistering(bridge: bridge))
    }

    @ViewBuilder
    private func bridgeStatusIcon(for bridge: BridgeInfo) -> some View {
        if registrationService.isRegistering(bridge: bridge) {
            ProgressView()
        } else if registrationService.isRegistered(bridge: bridge) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
        } else {
            Image(systemName: "chevron.right")
                .foregroundStyle(.quaternary)
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

#Preview {
    BridgesListView_iOS(bridges: [], bridgeManager: BridgeManager(), onManualEntryTapped: nil)
}
