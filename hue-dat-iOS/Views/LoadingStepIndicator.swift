//
//  LoadingStepIndicator.swift
//  hue dat iOS
//
//  Multi-step loading progress indicator with visual step tracking
//

import SwiftUI

struct LoadingStepIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            // Spinner
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            // Step indicators (circles)
            HStack(spacing: 12) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .scaleEffect(step == currentStep ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentStep)
                }
            }
            .padding(.top, 8)

            // Step counter and message
            VStack(spacing: 6) {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            LoadingStepIndicator(
                currentStep: 1,
                totalSteps: 4,
                message: "Connecting to bridge..."
            )

            LoadingStepIndicator(
                currentStep: 2,
                totalSteps: 4,
                message: "Loading rooms..."
            )

            LoadingStepIndicator(
                currentStep: 4,
                totalSteps: 4,
                message: "Loading scenes..."
            )
        }
    }
}
