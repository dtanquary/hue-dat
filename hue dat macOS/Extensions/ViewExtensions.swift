//
//  ViewExtensions.swift
//  hue dat macOS
//
//  Custom view modifiers for macOS UI
//

import SwiftUI

extension View {
    /// Applies a glass effect styling to the view (macOS version)
    /// Uses ultra-thin material background with subtle shadow for frosted glass appearance
    func glassEffect() -> some View {
        self
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
