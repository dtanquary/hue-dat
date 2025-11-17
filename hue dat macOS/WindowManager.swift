//
//  WindowManager.swift
//  hue dat macOS
//
//  Created for testing SwiftUI Window as alternative to NSPopover
//

import SwiftUI
import AppKit

@Observable
class WindowManager {
    var isWindowVisible: Bool = false
    var windowPosition: CGPoint = .zero

    // Environment actions captured from SwiftUI context
    var openWindowAction: ((String) -> Void)? {
        didSet {
            print("🎬 [WindowManager] openWindowAction was \(oldValue == nil ? "NIL" : "SET") → now \(openWindowAction == nil ? "NIL" : "SET")")
        }
    }
    var closeWindowAction: ((String) -> Void)? {
        didSet {
            print("🎬 [WindowManager] closeWindowAction was \(oldValue == nil ? "NIL" : "SET") → now \(closeWindowAction == nil ? "NIL" : "SET")")
        }
    }

    /// Calculate window position to appear below the menu bar button
    /// - Parameter button: The NSStatusBarButton to anchor to
    /// - Returns: CGPoint for window's bottom-left origin
    func calculatePosition(from button: NSStatusBarButton) -> CGPoint {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            return CGPoint(x: 100, y: 100) // Fallback position
        }

        // Get button's frame in screen coordinates
        let buttonFrame = buttonWindow.convertToScreen(button.frame)

        // Window dimensions (matching MenuBarPanelView)
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 480

        // Center window horizontally under the button
        let windowX = buttonFrame.midX - (windowWidth / 2)

        // Position window below menu bar (accounting for macOS coordinate system)
        // Menu bar is at top of screen, so we subtract height to position below
        let windowY = buttonFrame.minY - windowHeight - 8 // 8pt gap below menu bar

        // Ensure window stays on screen
        let screenFrame = screen.visibleFrame
        let clampedX = max(screenFrame.minX, min(windowX, screenFrame.maxX - windowWidth))
        let clampedY = max(screenFrame.minY, min(windowY, screenFrame.maxY - windowHeight))

        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Show the SwiftUI Window using environment action
    func showWindow(at position: CGPoint) {
        print("🪟 [WindowManager] showWindow called at position: \(position)")
        print("🪟 [WindowManager] openWindowAction is: \(openWindowAction == nil ? "NIL ❌" : "SET ✅")")
        windowPosition = position
        isWindowVisible = true
        if openWindowAction != nil {
            print("📱 [WindowManager] Calling openWindow(id: \"main-panel\")")
            openWindowAction?("main-panel")
        } else {
            print("⚠️ [WindowManager] Cannot open window - openWindowAction is nil!")
        }
    }

    /// Hide the SwiftUI Window using environment action
    func hideWindow() {
        print("🪟 [WindowManager] hideWindow called")
        print("🪟 [WindowManager] closeWindowAction is: \(closeWindowAction == nil ? "NIL ❌" : "SET ✅")")
        isWindowVisible = false
        if closeWindowAction != nil {
            print("📱 [WindowManager] Calling dismissWindow(id: \"main-panel\")")
            closeWindowAction?("main-panel")
        } else {
            print("⚠️ [WindowManager] Cannot close window - closeWindowAction is nil!")
        }
    }

    /// Toggle window visibility
    func toggleWindow(from button: NSStatusBarButton) {
        if isWindowVisible {
            hideWindow()
        } else {
            let position = calculatePosition(from: button)
            showWindow(at: position)
        }
    }
}
