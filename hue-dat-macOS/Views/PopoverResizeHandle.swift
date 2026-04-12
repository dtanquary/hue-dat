//
//  PopoverResizeHandle.swift
//  hue dat macOS
//
//  Custom NSView that provides a resize handle for the popover
//

import AppKit
import QuartzCore

class PopoverResizeHandle: NSView {
    weak var popover: NSPopover?

    private var isDragging = false
    private var dragStartMouseY: CGFloat = 0
    private var dragStartHeight: CGFloat = 0

    private let minHeight: CGFloat = 300

    // Throttle resize updates to reduce layout churn
    private var lastResizeTime: CFAbsoluteTime = 0
    private let resizeInterval: CFAbsoluteTime = 1.0 / 60.0

    // Track the target height so mouseUp can snap to exact position
    private var pendingHeight: CGFloat = 0

    // Get dynamic max height based on screen
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
        // Transparent background - invisible but still captures mouse events
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking area
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        // Create new tracking area for cursor updates
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .cursorUpdate
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        if let area = trackingArea {
            addTrackingArea(area)
        }
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

    override func mouseMoved(with event: NSEvent) {
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartMouseY = NSEvent.mouseLocation.y
        dragStartHeight = popover?.contentSize.height ?? 480
        pendingHeight = dragStartHeight
        lastResizeTime = 0
        NSCursor.resizeUpDown.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let popover = popover else { return }

        let currentMouseY = NSEvent.mouseLocation.y
        let deltaY = dragStartMouseY - currentMouseY

        // Direct manipulation: drag down (deltaY positive) = taller, drag up (deltaY negative) = shorter
        let newHeight = max(minHeight, min(maxHeight, dragStartHeight + deltaY))
        pendingHeight = newHeight

        // Throttle: skip this frame if too soon since last update
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastResizeTime >= resizeInterval else { return }
        lastResizeTime = now

        applyHeight(newHeight, to: popover)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()

        // Apply final height (un-throttled) to snap to exact drag position
        if let popover = popover {
            applyHeight(pendingHeight, to: popover)
        }

        PopoverSizeManager.shared.saveHeight(pendingHeight)
    }

    /// Apply a height to the popover with all animations suppressed.
    private func applyHeight(_ height: CGFloat, to popover: NSPopover) {
        let newSize = NSSize(width: 320, height: height)

        // Suppress all implicit animations at both Core Animation and AppKit levels
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false

        // Set both contentSize and preferredContentSize to prevent the
        // hosting controller's intrinsic size from fighting the popover
        popover.contentViewController?.preferredContentSize = newSize
        popover.contentSize = newSize

        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }
}
