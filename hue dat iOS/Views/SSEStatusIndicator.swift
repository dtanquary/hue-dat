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
    @ObservedObject var bridgeManager: BridgeManager
    @State private var streamState: StreamState = .idle
    @State private var cancellable: AnyCancellable?

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
            print("🟢 SSE Status Indicator appeared - subscribing to stream state")

            // Set initial state based on BridgeManager's connection status
            if bridgeManager.isSSEConnected {
                streamState = .connected
                print("🟢 SSE Status Indicator: Initial state set to connected")
            }

            subscribeToStreamState()
        }
        .onDisappear {
            cancellable?.cancel()
            cancellable = nil
        }
    }

    private var indicatorContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(colorForState)

            if streamState == .connecting {
                ProgressView()
                    .scaleEffect(0.7)
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
                print("⚠️ SSE Status Indicator: No connected bridge, skipping subscription")
                return
            }

            let service = HueAPIService.shared
            let streamSubject = await service.streamStateSubject

            await MainActor.run {
                cancellable = streamSubject
                    .receive(on: DispatchQueue.main)
                    .sink { state in
                        print("🟢 SSE Status Indicator: State changed to \(state)")
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
}

#Preview {
    SSEStatusIndicator(bridgeManager: BridgeManager())
}
