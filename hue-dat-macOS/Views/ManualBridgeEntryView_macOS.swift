//
//  ManualBridgeEntryView_macOS.swift
//  hue dat macOS
//
//  Manual bridge entry form
//

import SwiftUI
import HueDatShared

struct ManualBridgeEntryView_macOS: View {
    @Environment(\.dismiss) var dismiss

    @State private var ipAddress: String = ""
    @State private var bridgeName: String = ""
    @State private var showValidationError: Bool = false

    var onBridgeAdded: (BridgeInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("IP Address", text: $ipAddress)
                        .autocorrectionDisabled()
                        .onChange(of: ipAddress) { _, _ in
                            showValidationError = false
                        }
                        .onSubmit { addBridge() }

                    TextField("Name (Optional)", text: $bridgeName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Bridge Information")
                } footer: {
                    if showValidationError {
                        Text("Please enter a valid IP address (e.g., 192.168.1.2)")
                            .foregroundStyle(.red)
                    } else {
                        Text("Enter the IP address of your Philips Hue bridge. You can find this in the Hue app or your router's settings.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Bridge") {
                    addBridge()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ipAddress.isEmpty)
            }
            .padding()
        }
        .frame(width: 380, height: 280)
    }

    private func addBridge() {
        guard isValidIPAddress(ipAddress) else {
            showValidationError = true
            return
        }

        let bridgeInfo = BridgeInfo(
            id: "manual_" + ipAddress.replacingOccurrences(of: ".", with: "_"),
            internalipaddress: ipAddress.trimmingCharacters(in: .whitespaces),
            port: 443,
            serviceName: bridgeName.isEmpty ? nil : bridgeName.trimmingCharacters(in: .whitespaces)
        )

        onBridgeAdded(bridgeInfo)
        dismiss()
    }

    private func isValidIPAddress(_ ip: String) -> Bool {
        let octets = ip.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let value = Int(octet), !octet.isEmpty else { return false }
            return value >= 0 && value <= 255
        }
    }
}

#Preview {
    ManualBridgeEntryView_macOS { bridge in
        debugLog("Bridge added: \(bridge)")
    }
}
