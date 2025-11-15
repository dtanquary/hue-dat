//
//  AboutView_macOS.swift
//  hue dat macOS
//
//  About dialog for the macOS menu bar app
//

import SwiftUI
import AppKit

struct AboutView_macOS: View {
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // App icon (2x larger: 160×160)
            Group {
                if let nsImage = NSImage(named: "AppIcon") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                } else {
                    // Fallback to SF Symbol if icon not found
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.yellow, .orange)
                        .symbolRenderingMode(.palette)
                }
            }

            // App name, version, and build
            VStack(spacing: 6) {
                Text("HueDat")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Build \(appBuild)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Full description
            Text("HueDat is a native macOS and watchOS app for controlling Philips Hue lights. Control your lights directly from your menu bar without requiring the official Hue app.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            // Close button with glass effect and wider frame
            Button("OK") {
                if let onClose = onClose {
                    onClose()
                } else {
                    // Fallback: close the window directly
                    NSApp.keyWindow?.close()
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .frame(minWidth: 200)
            .glassEffect()
        }
        .padding(30)
        .frame(width: 420, height: 480)
    }

    // App version from bundle info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    // App build from bundle info
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

#Preview {
    AboutView_macOS()
}
