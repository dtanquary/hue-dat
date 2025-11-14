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

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState)
                .frame(width: 8, height: 8)

            if streamState == .connecting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .help(tooltipForState)
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

    private func subscribeToStreamState() {
        // Subscribe to stream state changes from HueAPIService
        Task {
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

    private var tooltipForState: String {
        switch streamState {
        case .connected:
            return "Live updates active"
        case .connecting:
            return "Connecting to live updates..."
        case .disconnected(let error):
            if let error = error {
                return "Disconnected: \(error.localizedDescription)"
            }
            return "Disconnected from live updates"
        case .error(let message):
            return "Error: \(message)"
        case .idle:
            return "Live updates not active"
        }
    }
}

#Preview {
    SSEStatusIndicator()
}
