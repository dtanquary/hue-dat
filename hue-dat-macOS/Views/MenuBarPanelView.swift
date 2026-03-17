//
//  MenuBarPanelView.swift
//  hue dat macOS
//
//  Main floating panel view for the menu bar app
//

import SwiftUI
import HueDatShared

struct MenuBarPanelView: View {
    @Environment(BridgeManager.self) var bridgeManager
    @Environment(PopoverEnvironment.self) var popoverEnvironment

    @State private var showBridgeSetup = false
    @State private var selectedRoomId: String?
    @State private var selectedZoneId: String?
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            if let roomId = selectedRoomId {
                // Room detail view
                GroupDetailView_macOS<HueRoom>(
                    groupId: roomId,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRoomId = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            } else if let zoneId = selectedZoneId {
                // Zone detail view
                GroupDetailView_macOS<HueZone>(
                    groupId: zoneId,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedZoneId = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            } else if showingSettings {
                // Settings view
                SettingsView_macOS(
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSettings = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            } else if bridgeManager.isConnected {
                // Connected state - show rooms and zones list
                RoomsZonesListView_macOS(
                    onRoomSelected: { room in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRoomId = room.id
                        }
                    },
                    onZoneSelected: { zone in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedZoneId = zone.id
                        }
                    },
                    onSettingsSelected: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSettings = true
                        }
                    }
                )
            } else {
                // Not connected - show setup
                disconnectedView
            }
        }
        .frame(width: 320)
        .frame(minHeight: 292, maxHeight: 992)  // Account for 8pt handle
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            // Add resize handle at the bottom
            if let popover = popoverEnvironment.popover {
                ResizeHandleView(popover: popover)
                    .frame(height: 8)
            }
        }
        .sheet(isPresented: $showBridgeSetup) {
            BridgeSetupView_macOS()
                .environment(bridgeManager)
        }
        // Note: About dialog is shown via NSWindow in AppDelegate (accessed from context menu)
        // Note: SSE lifecycle is now managed by AppDelegate for persistent background connection
        // The panel only needs to show connection status, not manage the stream
    }

    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Bridge Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to a Philips Hue bridge to control your lights")
                .font(.body)
                .foregroundStyle(.secondary)
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
    MenuBarPanelView()
        .environment(BridgeManager())
        .environment(PopoverEnvironment())
}
