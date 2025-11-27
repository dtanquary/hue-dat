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
            print("🔧 PopoverResizeHostingController: popover set to \(popover == nil ? "nil" : "set")")
            // Propagate popover reference to handle when it's set
            resizeHandle?.popover = popover
        }
    }

    func setupResizeHandle() {
        // Only setup once
        guard !isSetupComplete else {
            print("🔧 PopoverResizeHostingController: setupResizeHandle() - already setup, skipping")
            return
        }

        print("🔧 PopoverResizeHostingController: setupResizeHandle() started")

        // Get the hosting controller's content view
        let contentView = view
        print("🔧 PopoverResizeHostingController: Got content view with frame: \(contentView.frame)")
        print("🔧 PopoverResizeHostingController: Content view has \(contentView.subviews.count) subviews")

        // List all subviews BEFORE adding handle
        for (index, subview) in contentView.subviews.enumerated() {
            print("🔧 PopoverResizeHostingController: BEFORE - Subview \(index): \(type(of: subview)) - frame: \(subview.frame)")
        }

        // Create resize handle and add it directly to the content view
        let handle = PopoverResizeHandle()
        contentView.addSubview(handle, positioned: .above, relativeTo: nil)  // Add on top of all other views

        print("🔧 PopoverResizeHostingController: Added handle to content view, now has \(contentView.subviews.count) subviews")

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

        print("🔧 PopoverResizeHostingController: setupResizeHandle() completed - handle frame (before layout): \(handle.frame)")

        // Force layout and check frame
        contentView.layoutSubtreeIfNeeded()
        print("🔧 PopoverResizeHostingController: After layout - handle frame: \(handle.frame), bounds: \(handle.bounds)")
        print("🔧 PopoverResizeHostingController: Handle isHidden: \(handle.isHidden), alphaValue: \(handle.alphaValue)")

        // List all subviews for debugging
        for (index, subview) in contentView.subviews.enumerated() {
            print("🔧 PopoverResizeHostingController: AFTER - Subview \(index): \(type(of: subview)) - frame: \(subview.frame), z-order: \(index)")
        }
    }
}
