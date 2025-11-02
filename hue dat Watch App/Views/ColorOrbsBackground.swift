//
//  ColorOrbsBackground.swift
//  hue dat Watch App
//
//  Created by David Tanquary on 10/31/25.
//

import SwiftUI

/// Background view that displays gradient color orbs representing individual lights
/// Orbs are sized proportionally and positioned to fill the background without scrolling
struct ColorOrbsBackground: View {
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let position = calculatePosition(
                        index: index,
                        total: colors.count,
                        size: geometry.size
                    )
                    let orbSize = calculateOrbSize(
                        lightCount: colors.count,
                        availableHeight: geometry.size.height
                    )

                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [color, color.opacity(0)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: orbSize / 2
                            )
                        )
                        .frame(width: orbSize, height: orbSize)
                        .position(position)
                        .blendMode(.screen)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Calculate the size of each orb based on the number of lights and available space
    /// Fewer lights = larger orbs, more lights = smaller orbs
    private func calculateOrbSize(lightCount: Int, availableHeight: Double) -> Double {
        guard lightCount > 0 else { return 0 }

        // Base calculation: ensure orbs fill the space
        // For 1 light: use 80% of height
        // For multiple lights: scale down based on sqrt of count
        let baseSize = availableHeight * 0.8
        let scaleFactor = 1.0 / sqrt(Double(lightCount))
        let orbSize = baseSize * scaleFactor

        // Ensure a minimum size for visibility and maximum to prevent overflow
        return max(30, min(orbSize, availableHeight * 0.9))
    }

    /// Calculate the position for an orb using a circular/spiral pattern
    /// Distributes orbs evenly across the available space
    private func calculatePosition(index: Int, total: Int, size: CGSize) -> CGPoint {
        let centerX = size.width / 2
        let centerY = size.height / 2

        guard total > 0 else {
            return CGPoint(x: centerX, y: centerY)
        }

        // Single light - center it
        if total == 1 {
            return CGPoint(x: centerX, y: centerY)
        }

        // Two lights - place side by side
        if total == 2 {
            let spacing = size.width * 0.3
            let x = centerX + (index == 0 ? -spacing : spacing)
            return CGPoint(x: x, y: centerY)
        }

        // Three or more lights - use a circular arrangement
        // Place them in a circle around the center
        let radius = min(size.width, size.height) * 0.25
        let angle = (2.0 * .pi / Double(total)) * Double(index)

        let x = centerX + radius * cos(angle)
        let y = centerY + radius * sin(angle)

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
        ColorOrbsBackground(colors: [
            .red,
            .blue,
            .green
        ])

        Text("ON")
            .font(.system(size: 48, weight: .bold))
            .foregroundStyle(.white)
    }
}
