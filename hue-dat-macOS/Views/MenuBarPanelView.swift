//
//  MenuBarPanelView.swift
//  hue dat macOS
//
//  Main floating panel view for the menu bar app
//

import SwiftUI
import HueDatShared

/// Navigation destinations within the panel
enum PanelRoute: Hashable {
    case room(String)
    case zone(String)
    case settings
}

struct MenuBarPanelView: View {
    @Environment(BridgeManager.self) var bridgeManager
    @State private var showBridgeSetup = false
    @State private var path: [PanelRoute] = []

    var body: some View {
        VStack(spacing: 0) {
            // Custom ZStack router: NavigationStack doesn't animate pushes inside an
            // NSPopover, so we slide views manually for the iOS-style push transition.
            ZStack {
                Group {
                    if bridgeManager.isConnected {
                        RoomsZonesListView_macOS(
                            onRoomSelected: { room in path.append(.room(room.id)) },
                            onZoneSelected: { zone in path.append(.zone(zone.id)) },
                            onSettingsSelected: { path.append(.settings) }
                        )
                    } else {
                        disconnectedView
                    }
                }
                // iOS-style parallax: list drifts left and dims while a detail is pushed
                .offset(x: path.isEmpty ? 0 : -100)
                .overlay(Color.black.opacity(path.isEmpty ? 0 : 0.15))

                if let route = path.last {
                    Group {
                        switch route {
                        case .room(let id):
                            GroupDetailView_macOS<HueRoom>(groupId: id)
                        case .zone(let id):
                            GroupDetailView_macOS<HueZone>(groupId: id)
                        case .settings:
                            SettingsView_macOS()
                        }
                    }
                    .background() // opaque so the list doesn't show through during the slide
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.spring(duration: 0.35), value: path)
            .clipped()
            .environment(\.panelBack) {
                if !path.isEmpty { path.removeLast() }
            }
            .frame(maxHeight: .infinity)

            // Resize handle bar at the bottom
            resizeBar
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .onChange(of: bridgeManager.isConnected) { _, connected in
            // Pop any pushed detail/settings view when the bridge disconnects
            if !connected { path = [] }
        }
        .sheet(isPresented: $showBridgeSetup) {
            BridgeSetupView_macOS()
                .environment(bridgeManager)
        }
        // Note: About dialog is shown via NSWindow in AppDelegate (accessed from context menu)
        // Note: SSE lifecycle is now managed by AppDelegate for persistent background connection
        // The panel only needs to show connection status, not manage the stream
    }

    /// Visual-only resize bar. Drag interaction is handled by the AppDelegate's event monitor.
    private var resizeBar: some View {
        VStack(spacing: 0) {
            Divider()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
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
}
