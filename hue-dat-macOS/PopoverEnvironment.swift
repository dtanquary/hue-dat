//
//  PopoverEnvironment.swift
//  hue dat macOS
//
//  Environment object to share popover reference with SwiftUI views
//

import SwiftUI
import AppKit

@MainActor @Observable
class PopoverEnvironment {
    var popover: NSPopover?

    init(popover: NSPopover? = nil) {
        self.popover = popover
    }
}
