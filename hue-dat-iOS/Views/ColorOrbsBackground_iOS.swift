//
//  ColorOrbsBackground_iOS.swift
//  hue dat iOS
//
//  Ambient animated mesh backdrop driven by the group's live light color.
//  Pauses when Reduce Motion is on, the view is inactive, or lights are off
//  (a paused TimelineView still renders one static frame).
//

import SwiftUI
import HueDatShared

struct ColorOrbsBackground_iOS: View {
    let baseColor: Color
    let brightness: Double  // 0-100
    let isOn: Bool
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var meshColors: [Color] {
        let c = isOn ? baseColor : Color.gray
        return [
            .black, c.opacity(0.55), .black,
            c.opacity(0.4), c, c.opacity(0.5),
            .black, c.opacity(0.35), .black
        ]
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 20.0,
                                    paused: reduceMotion || !isActive || !isOn)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate / 8
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [Float(0.5 + 0.2 * sin(t * 0.7)), 0], [1, 0],
                        [0, Float(0.5 + 0.2 * cos(t * 0.8))],
                        [Float(0.5 + 0.3 * sin(t)), Float(0.5 + 0.3 * cos(t * 0.9))],
                        [1, Float(0.5 + 0.2 * sin(t * 0.6))],
                        [0, 1], [Float(0.5 + 0.2 * cos(t * 0.5)), 1], [1, 1]
                    ],
                    colors: meshColors
                )
            }
            .opacity(isOn ? 0.35 + 0.5 * (brightness / 100.0) : 0.15)
            .animation(.easeInOut(duration: 0.6), value: isOn)
            .animation(.easeInOut(duration: 0.6), value: brightness)
            .animation(.easeInOut(duration: 1.2), value: baseColor)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
