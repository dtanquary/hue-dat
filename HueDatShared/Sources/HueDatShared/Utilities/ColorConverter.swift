//
//  ColorConverter.swift
//  HueDatShared
//
//  Extracted from BridgeManager - pure color conversion functions
//  with no state dependency.
//

import SwiftUI

/// Pure-function color conversions for Hue XY and mirek color spaces.
public struct ColorConverter {

    /// Convert CIE XY color space to RGB
    /// Uses simplified conversion algorithm suitable for visual effects
    public static func xyToRGB(x: Double, y: Double, brightness: Double) -> Color {
        // Clamp values to valid ranges
        let x = max(0.0, min(1.0, x))
        let y = max(0.0, min(1.0, y))
        let brightness = max(0.0, min(100.0, brightness)) / 100.0

        // Avoid division by zero
        guard y > 0.0001 else {
            // Default to white if Y is too small
            return Color(red: brightness, green: brightness, blue: brightness)
        }

        // Calculate XYZ from xy
        let z = 1.0 - x - y
        let Y = brightness
        let X = (Y / y) * x
        let Z = (Y / y) * z

        // Convert XYZ to RGB using simplified sRGB matrix
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530

        // Apply gamma correction (simplified)
        r = r <= 0.0031308 ? 12.92 * r : (1.0 + 0.055) * pow(r, (1.0 / 2.4)) - 0.055
        g = g <= 0.0031308 ? 12.92 * g : (1.0 + 0.055) * pow(g, (1.0 / 2.4)) - 0.055
        b = b <= 0.0031308 ? 12.92 * b : (1.0 + 0.055) * pow(b, (1.0 / 2.4)) - 0.055

        // Clamp to valid RGB range
        r = max(0.0, min(1.0, r))
        g = max(0.0, min(1.0, g))
        b = max(0.0, min(1.0, b))

        return Color(red: r, green: g, blue: b)
    }

    /// Convert color temperature (mirek) to RGB
    /// Mirek = 1,000,000 / Kelvin
    public static func mirekToRGB(mirek: Int, brightness: Double) -> Color {
        // Convert mirek to Kelvin
        let kelvin = 1_000_000.0 / Double(mirek)
        let brightness = max(0.0, min(100.0, brightness)) / 100.0

        // Simplified color temperature to RGB
        // Based on approximate blackbody radiation
        var r: Double, g: Double, b: Double

        // Red calculation
        if kelvin <= 6600 {
            r = 1.0
        } else {
            let temp = kelvin / 100.0 - 60.0
            r = 329.698727446 * pow(temp, -0.1332047592)
            r = max(0.0, min(255.0, r)) / 255.0
        }

        // Green calculation
        if kelvin <= 6600 {
            let temp = kelvin / 100.0
            g = 99.4708025861 * log(temp) - 161.1195681661
            g = max(0.0, min(255.0, g)) / 255.0
        } else {
            let temp = kelvin / 100.0 - 60.0
            g = 288.1221695283 * pow(temp, -0.0755148492)
            g = max(0.0, min(255.0, g)) / 255.0
        }

        // Blue calculation
        if kelvin >= 6600 {
            b = 1.0
        } else if kelvin <= 1900 {
            b = 0.0
        } else {
            let temp = kelvin / 100.0 - 10.0
            b = 138.5177312231 * log(temp) - 305.0447927307
            b = max(0.0, min(255.0, b)) / 255.0
        }

        // Apply brightness
        r = r * brightness
        g = g * brightness
        b = b * brightness

        return Color(red: r, green: g, blue: b)
    }
}
