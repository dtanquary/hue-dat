//
//  EventMonitor.swift
//  hue dat macOS
//
//  Global event monitor for detecting clicks outside the popover
//

import Cocoa

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: () -> Void

    init(mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown], handler: @escaping () -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handler()
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
