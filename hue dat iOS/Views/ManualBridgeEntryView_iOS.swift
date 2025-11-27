//
//  ManualBridgeEntryView_iOS.swift
//  hue dat iOS
//
//  Manual bridge entry form
//

import SwiftUI
import HueDatShared

struct ManualBridgeEntryView_iOS: View {
    @Environment(\.dismiss) var dismiss

    @State private var ipAddress: String = ""
    @State private var bridgeName: String = ""
    @State private var showValidationError: Bool = false

    var onBridgeAdded: (BridgeInfo) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $ipAddress)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .onChange(of: ipAddress) { _, _ in
                            showValidationError = false
                        }

                    TextField("Name (Optional)", text: $bridgeName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Bridge Information")
                } footer: {
                    if showValidationError {
                        Text("Please enter a valid IP address (e.g., 192.168.1.2)")
                            .foregroundColor(.red)
                    } else {
                        Text("Enter the IP address of your Philips Hue bridge. You can find this in the Hue app or your router's settings.")
                    }
                }

                Section {
                    Button {
                        addBridge()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add Bridge")
                            Spacer()
                        }
                    }
                    .disabled(ipAddress.isEmpty)
                }
            }
            .navigationTitle("Add Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
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
    ManualBridgeEntryView_iOS { bridge in
        print("Bridge added: \(bridge)")
    }
}
