//
//  PopoverSizeManager.swift
//  hue dat macOS
//
//  Manages popover size persistence with validation and screen-aware clamping
//

import Foundation
import AppKit

/// Manages popover size persistence.
/// Marked @MainActor because NSScreen.main requires main thread access.
@MainActor
class PopoverSizeManager {
    static let shared = PopoverSizeManager()

    private let userDefaults = UserDefaults.standard
    private let popoverHeightKey = "PopoverHeight"

    private let defaultHeight: CGFloat = 480
    private let minHeight: CGFloat = 300
    private let absoluteMaxHeight: CGFloat = 1000  // Never exceed this
    private let width: CGFloat = 320

    private init() {
        debugLog("📐 [PopoverSizeManager] init - singleton created")
        // Listen for screen configuration changes (height will be clamped dynamically)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Note: No deinit needed - singleton is never deallocated
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
        let size = NSSize(width: width, height: savedHeight)
        debugLog("📐 [PopoverSizeManager] contentSize accessed: \(size)")
        return size
    }

    // MARK: - Screen Configuration Observer

    @objc private func screenConfigurationChanged() {
        // Height will be automatically clamped via savedHeight getter when accessed
        debugLog("📺 PopoverSizeManager: Screen configuration changed - height will be clamped if needed")
    }
}
