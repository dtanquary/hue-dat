//
//  SceneCarouselBackground.swift
//  hue dat Watch App
//
//  Scene carousel background with swipeable color orb visualizations
//

import SwiftUI

struct SceneCarouselBackground: View {
    let scenes: [HueScene]
    let fallbackColors: [Color]
    @Binding var currentIndex: Int
    let onSceneChange: (HueScene) -> Void
    @ObservedObject var bridgeManager: BridgeManager

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                let colors = bridgeManager.extractColorsFromScene(scene)
                ColorOrbsBackground(colors: colors.isEmpty ? fallbackColors : colors)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        // Enable hit testing so swipes work
        .allowsHitTesting(true)
        .onChange(of: currentIndex) { oldValue, newValue in
            // Activate scene when user swipes to it
            if newValue < scenes.count {
                let scene = scenes[newValue]
                onSceneChange(scene)
            }
        }
    }
}

struct ColorOrbsBackground: View {
    enum SizeMode {
        case fullscreen
        case compact
    }

    let colors: [Color]
    var size: SizeMode = .fullscreen

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()

                // Draw orbs for each color
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let position = orbPosition(for: index, total: colors.count, in: geometry.size)
                    let orbSize = self.orbSize(for: colors.count, in: geometry.size, mode: size)

                    RadialGradient(
                        gradient: Gradient(colors: [color, color.opacity(0.3), .clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize / 2
                    )
                    .frame(width: orbSize, height: orbSize)
                    .position(position)
                    .blendMode(.screen) // Additive blending for color mixing
                }
            }
        }
    }

    // Calculate position for each orb in a circular/spiral arrangement
    private func orbPosition(for index: Int, total: Int, in size: CGSize) -> CGPoint {
        let centerX = size.width / 2
        let centerY = size.height / 2

        if total == 1 {
            // Single orb in center
            return CGPoint(x: centerX, y: centerY)
        } else if total == 2 {
            // Two orbs side by side
            let offset = size.width * 0.25
            return CGPoint(
                x: index == 0 ? centerX - offset : centerX + offset,
                y: centerY
            )
        } else {
            // Multiple orbs in circular pattern
            let radius = min(size.width, size.height) * 0.35
            let angle = (2 * .pi / Double(total)) * Double(index) - .pi / 2

            return CGPoint(
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius
            )
        }
    }

    // Calculate orb size based on number of lights and available space
    private func orbSize(for count: Int, in size: CGSize, mode: SizeMode) -> CGFloat {
        let baseSize = min(size.width, size.height)

        let multiplier: CGFloat
        switch count {
        case 1:
            multiplier = mode == .fullscreen ? 2.5 : 1.2 // Very large or compact single orb
        case 2:
            multiplier = mode == .fullscreen ? 1.8 : 0.9 // Large or compact orbs
        case 3...4:
            multiplier = mode == .fullscreen ? 1.4 : 0.7 // Medium-large or small orbs
        default:
            multiplier = mode == .fullscreen ? 1.2 : 0.6 // Still large or very small for many lights
        }

        return baseSize * multiplier
    }
}
