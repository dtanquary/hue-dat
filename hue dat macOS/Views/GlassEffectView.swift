//
//  GlassEffectView.swift
//  hue dat macOS
//
//  NSViewRepresentable wrapper for NSGlassEffectView with private _variant API support
//

import SwiftUI
import AppKit

@available(macOS 15.0, *)
struct GlassEffectView: NSViewRepresentable {
    var variant: Int = 0  // 0-19 variants available via private API

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glassView = NSGlassEffectView()

        // Use private _variant API for fine-grained control (0-19)
        // This is undocumented but allows precise control over glass appearance
        if variant >= 0 && variant <= 19 {
            glassView.setValue(variant, forKey: "_variant")
        }

        return glassView
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        // Update variant if changed
        if variant >= 0 && variant <= 19 {
            nsView.setValue(variant, forKey: "_variant")
        }
    }
}

// SwiftUI modifier for easy application
extension View {
    @available(macOS 15.0, *)
    func glassBackground(variant: Int = 0) -> some View {
        self.background(GlassEffectView(variant: variant))
    }
}
