//
//  PopoverResizeHandle.swift
//  hue dat macOS
//
//  Transparent NSView overlaid on the bottom of the popover's hosting view.
//  Captures drag to resize the popover; the visible handle UI is rendered
//  by SwiftUI in MenuBarPanelView underneath this view.
//

import AppKit
import QuartzCore

class PopoverResizeHandle: NSView {
    weak var popover: NSPopover?

    private var isDragging = false
    private var dragStartMouseY: CGFloat = 0
    private var dragStartHeight: CGFloat = 0
    private var pendingHeight: CGFloat = 0

    private let minHeight: CGFloat = 300

    private var lastResizeTime: CFAbsoluteTime = 0
    private let resizeInterval: CFAbsoluteTime = 1.0 / 60.0

    private var maxHeight: CGFloat {
        PopoverSizeManager.shared.dynamicMaxHeight
    }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .cursorUpdate
        ]

        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartMouseY = NSEvent.mouseLocation.y
        dragStartHeight = popover?.contentSize.height ?? 480
        pendingHeight = dragStartHeight
        lastResizeTime = 0
        NSCursor.resizeUpDown.push()

        // Disable NSPopover's animation during drag to eliminate flicker.
        popover?.animates = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let popover = popover else { return }

        let currentMouseY = NSEvent.mouseLocation.y
        let deltaY = dragStartMouseY - currentMouseY

        // Drag down (deltaY positive) = taller, drag up = shorter.
        let newHeight = max(minHeight, min(maxHeight, dragStartHeight + deltaY))
        pendingHeight = newHeight

        // Throttle to ~60fps to reduce layout churn.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastResizeTime >= resizeInterval else { return }
        lastResizeTime = now

        applyHeight(newHeight, to: popover)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()

        guard let popover = popover else { return }

        // Apply final (un-throttled) height so the popover snaps to the exact release position.
        applyHeight(pendingHeight, to: popover)
        popover.animates = true

        PopoverSizeManager.shared.saveHeight(pendingHeight)
    }

    /// Apply a height to the popover with all implicit animations suppressed.
    /// Sets both `contentSize` and the view controller's `preferredContentSize`
    /// so NSPopover propagates the change through the window + content view
    /// instead of just nudging the window frame.
    private func applyHeight(_ height: CGFloat, to popover: NSPopover) {
        let newSize = NSSize(width: 320, height: height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false

        popover.contentViewController?.preferredContentSize = newSize
        popover.contentSize = newSize

        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }
}
