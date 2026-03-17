//
//  ResizeHandleView.swift
//  hue dat macOS
//
//  SwiftUI wrapper for the resize handle
//

import SwiftUI
import AppKit

struct ResizeHandleView: NSViewRepresentable {
    let popover: NSPopover

    func makeNSView(context: Context) -> PopoverResizeHandle {
        print("🔧 ResizeHandleView: makeNSView() called")
        let handle = PopoverResizeHandle()
        handle.popover = popover
        return handle
    }

    func updateNSView(_ nsView: PopoverResizeHandle, context: Context) {
        print("🔧 ResizeHandleView: updateNSView() called")
        nsView.popover = popover
    }
}
