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
    @Environment(BridgeManager.self) var bridgeManager
    @State private var streamState: StreamState = .idle
    @State private var displayedState: StreamState = .idle
    @State private var cancellable: AnyCancellable?
    @State private var pendingTransitionTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isAnimating: Bool = false

    // The Hue bridge periodically closes the long-lived SSE stream (NAT keepalive,
    // bridge-side stream age). Reconnect typically completes inside this window,
    // so holding the previous color avoids a red flash on each cycle.
    private static let disconnectDebounceInterval: Duration = .seconds(2)

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
            // CurrentValueSubject replays the current state on subscribe, so
            // no manual initial-state hack is needed.
            subscribeToStreamState()
        }
        .onDisappear {
            cancellable?.cancel()
            cancellable = nil
            pendingTransitionTask?.cancel()
            pendingTransitionTask = nil
        }
    }

    private var indicatorContent: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .foregroundStyle(colorForState)
            .frame(width: 8, height: 8)
            .opacity(displayedState == .connecting ? (isAnimating ? 0.3 : 1.0) : 1.0)
            .animation(
                displayedState == .connecting
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onChange(of: displayedState) { _, newState in
                if case .connecting = newState {
                    isAnimating = true
                } else {
                    isAnimating = false
                }
            }
    }

    private var isClickable: Bool {
        switch displayedState {
        case .disconnected, .error, .idle:
            return true
        case .connected, .connecting:
            return false
        }
    }

    private func handleReconnectClick() {
        debugLog("🔄 User clicked SSE status indicator - attempting reconnection")
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
                        applyStateChange(state)
                    }
            }
        }
    }

    // Hold green/blue through brief disconnect→reconnect cycles. .connected,
    // .connecting, and .idle settle immediately; .disconnected/.error wait
    // out the debounce window before painting red. Any new state during the
    // wait cancels the pending transition.
    @MainActor
    private func applyStateChange(_ newState: StreamState) {
        streamState = newState  // keep live for diagnostics
        pendingTransitionTask?.cancel()
        pendingTransitionTask = nil

        switch newState {
        case .connected, .connecting, .idle:
            displayedState = newState
        case .disconnected, .error:
            let target = newState
            pendingTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: Self.disconnectDebounceInterval)
                guard !Task.isCancelled else { return }
                displayedState = target
            }
        }
    }

    private var colorForState: Color {
        switch displayedState {
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
        switch displayedState {
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
        .environment(BridgeManager())
}
