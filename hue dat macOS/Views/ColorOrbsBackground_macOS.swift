//
//  ColorOrbsBackground_macOS.swift
//  hue dat macOS
//
//  Brightness-controlled background orb for macOS
//

import SwiftUI
import HueDatShared

struct ColorOrbsBackground_macOS: View {
    let brightness: Double  // 0-100
    let isOn: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black

                // Single centered orb
                let orbSize = min(geometry.size.width, geometry.size.height) * 2.5
                let orbColor = isOn ? Color.orange : Color.gray
                let orbOpacity = isOn ? (brightness / 100.0) : 0.2

                RadialGradient(
                    gradient: Gradient(colors: [
                        orbColor.opacity(orbOpacity),
                        orbColor.opacity(orbOpacity * 0.3),
                        .clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: orbSize / 2
                )
                .frame(width: orbSize, height: orbSize)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .blendMode(.screen)
                .animation(.easeInOut(duration: 0.3), value: brightness)
                .animation(.easeInOut(duration: 0.3), value: isOn)
            }
        }
    }
}
