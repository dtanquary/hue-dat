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
        VStack() {
            // 2-column layout: icon on left, text on right
            HStack(alignment: .top, spacing: 24) {
                // Left column: App icon
                Group {
                    if let nsImage = NSImage(named: "AppIcon") {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 160)
                    } else {
                        // Fallback to SF Symbol if icon not found
                        Image(systemName: "lightbulb.led.fill")
                            .font(.system(size: 120))
                            .foregroundStyle(.yellow, .orange)
                            .symbolRenderingMode(.palette)
                            .frame(width: 160, height: 160)
                    }
                }

                // Right column: Text content (left-justified)
                VStack(alignment: .leading, spacing: 0) {
                    // App name with large title style
                    Text("HueDat")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    // Version and build
                    HStack(alignment: .top, spacing: 4) {
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("(Build \(appBuild))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)

                    // Description
                    Text("HueDat is a native macOS and watchOS app for controlling Philips Hue lights. Control your lights directly from your menu bar without requiring the official Hue app.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(30)
        .frame(width: 500)
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
