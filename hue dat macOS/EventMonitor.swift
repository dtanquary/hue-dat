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
        debugLogSync("👁️ [EventMonitor] init - creating event monitor")
        self.mask = mask
        self.handler = handler
    }

    deinit {
        debugLogSync("👁️ [EventMonitor] deinit - starting")
        stop()
        debugLogSync("👁️ [EventMonitor] deinit - completed")
    }

    func start() {
        debugLogSync("👁️ [EventMonitor] start() called - monitor exists: \(monitor != nil)")
        guard monitor == nil else {
            debugLogSync("👁️ [EventMonitor] start() - monitor already exists, returning")
            return
        }

        debugLogSync("👁️ [EventMonitor] start() - adding global monitor for events")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            debugLogSync("👁️ [EventMonitor] Global event detected - calling handler")
            self?.handler()
        }
        debugLogSync("👁️ [EventMonitor] start() - monitor added: \(monitor != nil)")
    }

    func stop() {
        debugLogSync("👁️ [EventMonitor] stop() called - monitor exists: \(monitor != nil)")
        if let monitor = monitor {
            debugLogSync("👁️ [EventMonitor] stop() - removing monitor")
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            debugLogSync("👁️ [EventMonitor] stop() - monitor removed")
        } else {
            debugLogSync("👁️ [EventMonitor] stop() - no monitor to remove")
        }
    }
}
