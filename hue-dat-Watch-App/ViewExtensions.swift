//
//  ViewExtensions.swift
//  hue dat Watch App
//
//  Custom view modifiers for watchOS UI
//

import SwiftUI

extension View {
    /// Applies a skeleton loading shimmer effect to the view
    /// Shows an animated gradient overlay to indicate loading state
    func skeletonLoader(isActive: Bool) -> some View {
        self.modifier(SkeletonLoaderModifier(isActive: isActive))
    }
}

// MARK: - Skeleton Loader Modifier

struct SkeletonLoaderModifier: ViewModifier {
    let isActive: Bool
    @State private var startPoint: UnitPoint = .leading
    @State private var endPoint: UnitPoint = .trailing

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.primary.opacity(0.0), location: 0),
                            .init(color: Color.primary.opacity(0.12), location: 0.5),
                            .init(color: Color.primary.opacity(0.0), location: 1)
                        ]),
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            startPoint = .trailing
                            endPoint = UnitPoint(x: 2, y: 0)
                        }
                    }
                }
            }
    }
}
