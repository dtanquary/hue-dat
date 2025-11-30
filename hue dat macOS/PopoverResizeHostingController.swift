//
//  PopoverResizeHostingController.swift
//  hue dat macOS
//
//  Custom NSHostingController that integrates SwiftUI content with resize handle
//

import SwiftUI
import AppKit

class PopoverResizeHostingController<Content: View>: NSHostingController<Content> {
    private var resizeHandle: PopoverResizeHandle?
    private var isSetupComplete = false

    weak var popover: NSPopover? {
        didSet {
            // Propagate popover reference to handle when it's set
            resizeHandle?.popover = popover
        }
    }

    func setupResizeHandle() {
        // Only setup once
        guard !isSetupComplete else {
            return
        }

        // Get the hosting controller's content view
        let contentView = view

        // Create resize handle and add it directly to the content view
        let handle = PopoverResizeHandle()
        contentView.addSubview(handle, positioned: .above, relativeTo: nil)  // Add on top of all other views

        // Setup constraints for handle
        handle.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Resize handle at bottom, 8pt height, full width
            handle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            handle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            handle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            handle.heightAnchor.constraint(equalToConstant: 8)
        ])

        resizeHandle = handle

        // Set popover reference on handle
        handle.popover = popover

        isSetupComplete = true

        // Force layout
        contentView.layoutSubtreeIfNeeded()
    }
}
