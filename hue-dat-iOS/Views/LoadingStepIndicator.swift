//
//  LoadingStepIndicator.swift
//  hue dat iOS
//
//  Glass loading card with spinner and message
//

import SwiftUI

struct LoadingCard: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(24)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        LoadingCard(message: "Connecting to bridge...")
    }
}
