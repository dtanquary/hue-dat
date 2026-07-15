//
//  SSEStatusIndicator.swift
//  hue dat iOS
//
//  SSE connection status indicator for toolbar
//

import SwiftUI
import HueDatShared
import Combine

struct SSEStatusIndicator: View {
    var bridgeManager: BridgeManager
    @State private var streamState: StreamState = .idle
    @State private var displayedState: StreamState = .idle
    @State private var cancellable: AnyCancellable?
    @State private var pendingTransitionTask: Task<Void, Never>?

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
            } else {
                indicatorContent
            }
        }
        .onAppear {
            debugLog("🟢 SSE Status Indicator appeared - subscribing to stream state")
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
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(colorForState)

            if displayedState == .connecting {
                ProgressView()
                    .scaleEffect(0.7)
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
                debugLog("⚠️ SSE Status Indicator: No connected bridge, skipping subscription")
                return
            }

            let service = HueAPIService.shared
            let streamSubject = await service.streamStateSubject

            await MainActor.run {
                cancellable = streamSubject
                    .receive(on: DispatchQueue.main)
                    .sink { state in
                        debugLog("🟢 SSE Status Indicator: State changed to \(state)")
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
}

#Preview {
    SSEStatusIndicator(bridgeManager: BridgeManager())
}
