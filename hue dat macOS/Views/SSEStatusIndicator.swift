//
//  SSEStatusIndicator.swift
//  hue dat macOS
//
//  SSE connection status indicator for menu bar panel
//

import SwiftUI
import HueDatShared
import Combine

struct SSEStatusIndicator: View {
    @EnvironmentObject var bridgeManager: BridgeManager
    @State private var streamState: StreamState = .idle
    @State private var cancellable: AnyCancellable?
    @State private var isHovering: Bool = false
    @State private var isAnimating: Bool = false

    var body: some View {
        Group {
            if isClickable {
                Button(action: handleReconnectClick) {
                    indicatorContent
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 0.7 : 1.0)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            } else {
                indicatorContent
            }
        }
        .help(tooltipForState)
        .onAppear {
            // Set initial state based on BridgeManager's connection status
            if bridgeManager.isSSEConnected {
                streamState = .connected
            }

            subscribeToStreamState()
        }
        .onDisappear {
            cancellable?.cancel()
            cancellable = nil
        }
    }

    private var indicatorContent: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .foregroundStyle(colorForState)
            .frame(width: 8, height: 8)
            .opacity(streamState == .connecting ? (isAnimating ? 0.3 : 1.0) : 1.0)
            .animation(
                streamState == .connecting
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onChange(of: streamState) { newState in
                if case .connecting = newState {
                    isAnimating = true
                } else {
                    isAnimating = false
                }
            }
    }

    private var isClickable: Bool {
        switch streamState {
        case .disconnected, .error, .idle:
            return true
        case .connected, .connecting:
            return false
        }
    }

    private func handleReconnectClick() {
        print("🔄 User clicked SSE status indicator - attempting reconnection")
        Task {
            await bridgeManager.reconnectSSE()
        }
    }

    private func subscribeToStreamState() {
        // Subscribe to stream state changes from HueAPIService
        Task {
            // Guard against preview/test mode where bridge might not be connected
            guard bridgeManager.connectedBridge != nil else {
                return
            }

            let service = HueAPIService.shared
            let streamSubject = await service.streamStateSubject

            await MainActor.run {
                cancellable = streamSubject
                    .receive(on: DispatchQueue.main)
                    .sink { state in
                        streamState = state
                    }
            }
        }
    }

    private var colorForState: Color {
        switch streamState {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected, .error:
            return .red
        case .idle:
            return .gray.opacity(0.5)
        }
    }

    private var tooltipForState: String {
        switch streamState {
        case .connected:
            return "Live updates active"
        case .connecting:
            return "Connecting to live updates..."
        case .disconnected(let error):
            if let error = error {
                return "Disconnected: \(error.localizedDescription)\nClick to reconnect"
            }
            return "Disconnected from live updates\nClick to reconnect"
        case .error(let message):
            return "Error: \(message)\nClick to reconnect"
        case .idle:
            return "Live updates not active\nClick to connect"
        }
    }
}

#Preview {
    SSEStatusIndicator()
        .environmentObject(BridgeManager())
}
