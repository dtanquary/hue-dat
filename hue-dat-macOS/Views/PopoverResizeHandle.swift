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
        dragStartHeight = popover?.contentViewController?.view.window?.frame.size.height
            ?? popover?.contentSize.height ?? 480
        NSCursor.resizeUpDown.push()

        // Disable window animations for the duration of the drag
        if let window = popover?.contentViewController?.view.window {
            window.animationBehavior = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging,
              let window = popover?.contentViewController?.view.window else { return }

        let currentMouseY = NSEvent.mouseLocation.y
        let deltaY = dragStartMouseY - currentMouseY

        // Direct manipulation: drag down (deltaY positive) = taller, drag up (deltaY negative) = shorter
        let newHeight = max(minHeight, min(maxHeight, dragStartHeight + deltaY))

        // Resize the popover's underlying window directly.
        // This bypasses popover.contentSize, which would trigger
        // NSHostingController re-layout and cause flickering.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var frame = window.frame
        let heightDelta = newHeight - frame.size.height
        // Popover grows downward from menu bar, so adjust origin upward
        frame.origin.y -= heightDelta
        frame.size.height = newHeight
        window.setFrame(frame, display: true, animate: false)

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()

        guard let popover = popover,
              let window = popover.contentViewController?.view.window else { return }

        let finalHeight = window.frame.size.height

        // Restore window animation behavior
        window.animationBehavior = .utilityWindow

        // Commit the final size through popover.contentSize once (single layout pass)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        popover.contentSize = NSSize(width: 320, height: finalHeight)
        NSAnimationContext.endGrouping()

        PopoverSizeManager.shared.saveHeight(finalHeight)
    }
}
