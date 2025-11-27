//
//  PopoverSizeManager.swift
//  hue dat macOS
//
//  Manages popover size persistence with validation and screen-aware clamping
//

import Foundation
import AppKit

@MainActor
class PopoverSizeManager {
    static let shared = PopoverSizeManager()

    private let userDefaults = UserDefaults.standard
    private let popoverHeightKey = "PopoverHeight"
    private let screenResolutionKey = "PopoverScreenResolution"

    private let defaultHeight: CGFloat = 480
    private let minHeight: CGFloat = 300
    private let absoluteMaxHeight: CGFloat = 1000  // Never exceed this
    private let width: CGFloat = 320

    private init() {
        // Check if screen resolution has changed and reset if needed
        checkAndResetIfResolutionChanged()

        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Get the maximum allowed height based on current screen
    var dynamicMaxHeight: CGFloat {
        guard let screen = NSScreen.main else {
            return absoluteMaxHeight
        }

        // visibleFrame already excludes menu bar and dock
        // Use 85% to leave some breathing room at top/bottom
        let screenBasedMax = screen.visibleFrame.height * 0.85

        // Never exceed absolute maximum
        return min(absoluteMaxHeight, screenBasedMax)
    }

    /// Get the saved height with validation and screen-aware clamping
    var savedHeight: CGFloat {
        let saved = userDefaults.double(forKey: popoverHeightKey)

        // Return default if no saved value exists
        if saved == 0 {
            return defaultHeight
        }

        // Clamp to current screen constraints
        let maxAllowed = dynamicMaxHeight
        return max(minHeight, min(maxAllowed, saved))
    }

    /// Save height to UserDefaults with validation
    func saveHeight(_ height: CGFloat) {
        let maxAllowed = dynamicMaxHeight
        let clampedHeight = max(minHeight, min(maxAllowed, height))
        userDefaults.set(clampedHeight, forKey: popoverHeightKey)
    }

    /// Get the content size for NSPopover initialization
    var contentSize: NSSize {
        NSSize(width: width, height: savedHeight)
    }

    // MARK: - Screen Resolution Tracking

    private func currentScreenResolution() -> String? {
        guard let screen = NSScreen.main else { return nil }
        let frame = screen.frame
        return "\(Int(frame.width))x\(Int(frame.height))"
    }

    private func checkAndResetIfResolutionChanged() {
        let currentResolution = currentScreenResolution()
        let savedResolution = userDefaults.string(forKey: screenResolutionKey)

        // If resolution changed or this is first launch
        if let current = currentResolution, current != savedResolution {
            print("📺 PopoverSizeManager: Screen resolution changed from \(savedResolution ?? "none") to \(current) - resetting to default")
            resetToDefault()
            if let resolution = currentResolution {
                userDefaults.set(resolution, forKey: screenResolutionKey)
            }
        }
    }

    @objc private func screenConfigurationChanged() {
        print("📺 PopoverSizeManager: Screen configuration changed")
        checkAndResetIfResolutionChanged()
    }

    private func resetToDefault() {
        userDefaults.removeObject(forKey: popoverHeightKey)
        print("📺 PopoverSizeManager: Reset to default height (\(defaultHeight))")
    }
}
