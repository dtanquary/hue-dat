//
//  HueDatMacApp.swift
//  hue dat macOS
//
//  macOS MenuBar app entry point
//

import SwiftUI
import HueDatShared
import AppKit
import Cocoa

@main
struct HueDatMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - all UI handled by AppDelegate
        Settings {
            EmptyView()
        }
    }
}

class GlassPopoverViewController: NSViewController {

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .popover // Or .hud, .popover, etc. for different effects
        visualEffectView.blendingMode = .behindWindow // Ensures proper blending
        visualEffectView.state = .active // Ensure the effect is always active

        // Set the visualEffectView as the primary view for the controller
        self.view = visualEffectView

        // Add your actual popover content as subviews to visualEffectView
        let label = NSTextField(labelWithString: "Hello from the Glass Popover!")
        label.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor)
        ])
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var bridgeManager: BridgeManager!
    var aboutWindow: NSWindow?
    var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize bridge manager on main thread
        bridgeManager = BridgeManager()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "HueDat")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover for main panel
        setupPopover()
    }

    func setupPopover() {
        let popover = NSPopover()
        popover.contentViewController = GlassPopoverViewController()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient

        let contentView = MenuBarPanelView(showAboutDialog: .constant(false))
            .environmentObject(bridgeManager)

        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }

    @objc func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp:
            togglePopover()
        default:
            break
        }
    }

    func togglePopover() {
        if let popover = popover {
            if popover.isShown {
                closePopover()
            } else {
                showPopover()
            }
        }
    }

    func showPopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        // Critical: Activate app to ensure transient behavior works
        NSApp.activate(ignoringOtherApps: true)

        // Show popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Start event monitor to catch outside clicks
        eventMonitor = EventMonitor { [weak self] in
            self?.closePopover()
        }
        eventMonitor?.start()
    }

    func closePopover() {
        popover?.performClose(nil)
        eventMonitor?.stop()
        eventMonitor = nil
    }

    // MARK: - App State Monitoring

    func applicationWillResignActive(_ notification: Notification) {
        // Close popover when app loses focus for additional reliability
        closePopover()
    }

    func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "About HueDat",
            action: #selector(showAboutDialog),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit HueDat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func showAboutDialog() {
        // Close existing about window if open
        aboutWindow?.close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About HueDat"
        window.isReleasedWhenClosed = false

        let contentView = AboutView_macOS(onClose: { [weak self] in
            self?.aboutWindow?.close()
            self?.aboutWindow = nil
        })

        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.aboutWindow = window
    }
}
