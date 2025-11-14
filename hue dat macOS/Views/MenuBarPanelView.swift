//
//  MenuBarPanelView.swift
//  hue dat macOS
//
//  Main floating panel view for the menu bar app
//

import SwiftUI
import HueDatShared

struct MenuBarPanelView: View {
    @EnvironmentObject var bridgeManager: BridgeManager
    @Binding var showAboutDialog: Bool

    @State private var showBridgeSetup = false

    var body: some View {
        VStack(spacing: 0) {
            if bridgeManager.isConnected {
                // Connected state - show rooms and zones
                RoomsZonesListView_macOS()
            } else {
                // Not connected - show setup
                disconnectedView
            }
        }
        .frame(width: 320, height: 480)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showBridgeSetup) {
            BridgeSetupView_macOS()
                .environmentObject(bridgeManager)
        }
        .sheet(isPresented: $showAboutDialog) {
            AboutView_macOS()
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Bridge Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to a Philips Hue bridge to control your lights")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Connect to Bridge") {
                showBridgeSetup = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    MenuBarPanelView(showAboutDialog: .constant(false))
        .environmentObject(BridgeManager())
}
