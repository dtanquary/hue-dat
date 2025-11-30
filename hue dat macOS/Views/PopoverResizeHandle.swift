//
//  PopoverResizeHandle.swift
//  hue dat macOS
//
//  Custom NSView that provides a resize handle for the popover
//

import AppKit

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
        dragStartHeight = popover?.contentSize.height ?? 480
        NSCursor.resizeUpDown.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let currentMouseY = NSEvent.mouseLocation.y
        let deltaY = dragStartMouseY - currentMouseY

        // Direct manipulation: drag down (deltaY positive) = taller, drag up (deltaY negative) = shorter
        let newHeight = max(minHeight, min(maxHeight, dragStartHeight + deltaY))

        popover?.contentSize = NSSize(width: 320, height: newHeight)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        NSCursor.pop()

        if let height = popover?.contentSize.height {
            Task { @MainActor in
                PopoverSizeManager.shared.saveHeight(height)
            }
        }
    }
}
