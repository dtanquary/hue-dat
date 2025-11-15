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
import Combine

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

        // Start SSE stream in background if bridge is connected
        Task {
            await initializeSSEConnection()
        }

        // Observe connection state changes to manage SSE lifecycle
        observeConnectionChanges()
    }

    func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
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

        // Recreate content view controller for fresh material rendering
        let contentView = MenuBarPanelView(showAboutDialog: .constant(false))
            .environmentObject(bridgeManager)
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Critical: Activate app to ensure transient behavior works
        NSApp.activate(ignoringOtherApps: true)

        // Show popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Explicitly ensure popover window gets keyboard focus
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.makeKey()
        }

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

    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 App terminating - cleaning up SSE stream")
        Task {
            await stopSSEStream()
        }
        connectionObserver?.cancel()
        connectionObserver = nil
    }

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

        statusItem?.popUpMenu(menu)
    }

    @objc func showAboutDialog() {
        // If window already exists and is visible, just bring it to front
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Clean up any existing window properly
        if let existingWindow = aboutWindow {
            existingWindow.contentView = nil
            existingWindow.close()
            aboutWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let contentView = AboutView_macOS(onClose: { [weak self] in
            guard let self = self else { return }
            if let window = self.aboutWindow {
                window.contentView = nil
                window.close()
            }
            self.aboutWindow = nil
        })

        window.contentView = NSHostingController(rootView: contentView).view

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.aboutWindow = window
    }

    // MARK: - SSE Lifecycle Management

    private var connectionObserver: AnyCancellable?
    private var isSSEStreamActive = false

    private func initializeSSEConnection() async {
        guard bridgeManager.isConnected else {
            print("ℹ️ No bridge connected - skipping SSE initialization")
            return
        }

        print("🔍 Initializing SSE connection on app launch...")

        // Validate connection to ensure HueAPIService is configured
        await bridgeManager.validateConnection()

        guard bridgeManager.isConnectionValidated else {
            print("⚠️ Connection validation failed - not starting SSE")
            return
        }

        await startSSEStream()
    }

    private func observeConnectionChanges() {
        connectionObserver = bridgeManager.$connectedBridge
            .sink { [weak self] bridge in
                guard let self = self else { return }
                if bridge != nil {
                    Task {
                        await self.handleConnectionEstablished()
                    }
                } else {
                    Task {
                        await self.handleConnectionLost()
                    }
                }
            }
    }

    private func handleConnectionEstablished() async {
        print("🔗 Bridge connected - starting SSE stream...")
        await bridgeManager.validateConnection()

        guard bridgeManager.isConnectionValidated else {
            print("⚠️ Connection validation failed")
            return
        }

        await startSSEStream()
    }

    private func handleConnectionLost() async {
        print("🔌 Bridge disconnected - stopping SSE stream...")
        await stopSSEStream()
    }

    private func startSSEStream() async {
        // Prevent duplicate SSE streams
        if isSSEStreamActive {
            print("⚠️ SSE stream already active - skipping duplicate start")
            return
        }

        print("🟢 Starting background SSE stream and event listeners")

        // Start listening to SSE events in BridgeManager
        bridgeManager.startListeningToSSEEvents()

        // Start the actual SSE stream
        do {
            try await HueAPIService.shared.startEventStream()
            isSSEStreamActive = true
            print("✅ Background SSE stream started successfully")
        } catch {
            print("❌ Failed to start SSE stream: \(error.localizedDescription)")
            isSSEStreamActive = false
        }
    }

    private func stopSSEStream() async {
        guard isSSEStreamActive else {
            print("ℹ️ SSE stream not active - nothing to stop")
            return
        }

        print("🔴 Stopping background SSE stream and event listeners")

        // Stop listening to SSE events
        bridgeManager.stopListeningToSSEEvents()

        // Stop the SSE stream
        await HueAPIService.shared.stopEventStream()
        isSSEStreamActive = false
        print("✅ Background SSE stream stopped")
    }
}
