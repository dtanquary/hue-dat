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
        VStack(spacing: 20) {
            // App icon
            Group {
                if let nsImage = NSImage(named: "AppIcon") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else {
                    // Fallback to SF Symbol if icon not found
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.yellow, .orange)
                        .symbolRenderingMode(.palette)
                }
            }

            // App name and version
            VStack(spacing: 4) {
                Text("HueDat")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Description
            Text("Control your Philips Hue lights from your Mac's menu bar")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()
                .padding(.vertical, 8)

            // Close button
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
        }
        .padding(30)
        .frame(width: 400, height: 320)
    }
}

#Preview {
    AboutView_macOS()
}
