//
//  ManualBridgeEntryView.swift
//  hue dat Watch App
//
//  Created on 2025-11-05.
//

import SwiftUI
import HueDatShared

struct ManualBridgeEntryView: View {
    @Environment(\.dismiss) var dismiss

    @State private var ipAddress: String = ""
    @State private var bridgeName: String = ""
    @State private var showValidationError: Bool = false

    var onBridgeAdded: (BridgeInfo) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // IP Address field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("IP Address")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("192.168.1.2", text: $ipAddress)
                            .onChange(of: ipAddress) { _, _ in
                                showValidationError = false
                            }
                    }

                    // Optional name field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("My Bridge", text: $bridgeName)
                    }

                    // Validation error
                    if showValidationError {
                        Text("Please enter a valid IP address")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    // Add button
                    Button {
                        addBridge()
                    } label: {
                        Text("Add Bridge")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .disabled(ipAddress.isEmpty)
                    .glassEffect()

                    // Cancel button
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .glassEffect()
                }
                .padding()
            }
            .navigationTitle("Add Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func addBridge() {
        // Validate IP address format
        guard isValidIPAddress(ipAddress) else {
            showValidationError = true
            return
        }

        // Create BridgeInfo from manual input
        let bridgeInfo = BridgeInfo(
            id: generateBridgeId(from: ipAddress),
            internalipaddress: ipAddress.trimmingCharacters(in: .whitespaces),
            port: 443,
            serviceName: bridgeName.isEmpty ? nil : bridgeName.trimmingCharacters(in: .whitespaces)
        )

        // Pass the bridge info back to parent
        onBridgeAdded(bridgeInfo)

        // Dismiss the sheet
        dismiss()
    }

    private func isValidIPAddress(_ ip: String) -> Bool {
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#

        guard let regex = try? NSRegularExpression(pattern: ipPattern),
              regex.firstMatch(in: ip, range: NSRange(ip.startIndex..., in: ip)) != nil else {
            return false
        }

        // Validate each octet is between 0-255
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }

        return octets.allSatisfy { $0 >= 0 && $0 <= 255 }
    }

    private func generateBridgeId(from ip: String) -> String {
        // Generate a pseudo-ID from the IP address
        // Format: "manual_" + IP with dots replaced by underscores
        return "manual_" + ip.replacingOccurrences(of: ".", with: "_")
    }
}

#Preview {
    ManualBridgeEntryView { bridge in
        print("Bridge added: \(bridge)")
    }
}
