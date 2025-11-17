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
        // MARK: - SwiftUI Window Alternative (for testing vs NSPopover)
        // This window can be used instead of NSPopover by uncommenting the line
        // in AppDelegate's togglePopover() method
        Window("HueDat Panel", id: "main-panel") {
            if let windowManager = appDelegate.windowManager {
                WindowControllerView(windowManager: windowManager)
                    .frame(width: 0, height: 0)  // Invisible helper

                MenuBarPanelView()
                    .environmentObject(appDelegate.bridgeManager)
                    .frame(width: 320, height: 480)
                    .onAppear {
                        print("🖼️ [MenuBarPanelView] onAppear - window content appeared")
                        print("🔍 [MenuBarPanelView] Available windows: \(NSApp.windows.map { "\($0.title) (level: \($0.level.rawValue))" })")

                        // Configure window after it's created
                        if let window = NSApp.windows.first(where: { $0.title == "HueDat Panel" }) {
                            print("✅ [MenuBarPanelView] Found window: '\(window.title)'")
                            window.level = .floating
                            window.styleMask = [.borderless, .fullSizeContentView]
                            window.isOpaque = false
                            window.backgroundColor = .clear
                            window.hasShadow = true
                            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

                            // Set position
                            print("📍 [MenuBarPanelView] Setting window position to: \(windowManager.windowPosition)")
                            window.setFrameOrigin(windowManager.windowPosition)
                        } else {
                            print("❌ [MenuBarPanelView] Could not find window with title 'HueDat Panel'")
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 480)
        .defaultPosition(.topLeading)

        // Empty Settings scene - all UI handled by AppDelegate or Window above
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Window Controller Helper View
/// Invisible helper view that captures SwiftUI environment actions
/// and makes them available to WindowManager
struct WindowControllerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let windowManager: WindowManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                print("🎬 [WindowControllerView] onAppear - capturing environment actions")
                // Capture environment actions in WindowManager
                windowManager.openWindowAction = { id in
                    print("📱 [WindowControllerView] openWindow closure called with id: \(id)")
                    openWindow(id: id)
                }
                windowManager.closeWindowAction = { id in
                    print("📱 [WindowControllerView] dismissWindow closure called with id: \(id)")
                    dismissWindow(id: id)
                }
                print("✅ [WindowControllerView] Environment actions captured successfully")
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

    // MARK: - SwiftUI Window Alternative Properties
    var windowManager: WindowManager?

    // UserDefaults key for tracking popover open timestamps
    private let lastPopoverOpenKey = "LastPopoverOpenTimestamp"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize bridge manager on main thread
        bridgeManager = BridgeManager()

        // Initialize window manager for SwiftUI Window alternative
        windowManager = WindowManager()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lightbulb.led.fill", accessibilityDescription: "HueDat")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover for main panel
        setupPopover()

        // Start SSE stream in background if bridge is connected
        Task {
            await initializeSSEConnection()

            // Load data in background after SSE starts
            if bridgeManager.isConnected {
                await bridgeManager.refreshAllData()
            }
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
        // ╔═══════════════════════════════════════════════════════════════════════╗
        // ║  TESTING: NSPopover vs SwiftUI Window                                 ║
        // ╠═══════════════════════════════════════════════════════════════════════╣
        // ║  To test SwiftUI Window instead of NSPopover:                         ║
        // ║  1. Comment out the NSPopover code block below (lines 138-144)        ║
        // ║  2. Uncomment the SwiftUI Window line (line 147)                      ║
        // ║                                                                        ║
        // ║  TRADEOFFS:                                                            ║
        // ║  NSPopover (current):                                                  ║
        // ║    ✅ Automatic positioning anchored to menu bar button               ║
        // ║    ✅ Built-in arrow indicator pointing to menu bar                   ║
        // ║    ✅ Auto-dismiss (.transient behavior) is robust                    ║
        // ║    ✅ Purpose-built for menu bar applications                         ║
        // ║                                                                        ║
        // ║  SwiftUI Window (alternative):                                         ║
        // ║    ✅ Modern SwiftUI APIs                                             ║
        // ║    ✅ Consistent with Apple's latest design direction                 ║
        // ║    ❌ Manual positioning calculation required                         ║
        // ║    ❌ No arrow indicator (plain rectangle)                            ║
        // ║    ❌ Custom dismiss logic needed                                     ║
        // ║    ❌ More complex window lifecycle management                        ║
        // ║                                                                        ║
        // ║  NOTE: You still need AppKit for NSStatusItem either way!             ║
        // ╚═══════════════════════════════════════════════════════════════════════╝

        // CURRENT: NSPopover implementation
        if let popover = popover {
            if popover.isShown {
                closePopover()
            } else {
                showPopover()
            }
        }

        // ALTERNATIVE: Uncomment this line to test SwiftUI Window instead
        // toggleSwiftUIWindow()
    }

    func showPopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        // Recreate content view controller for fresh material rendering
        let contentView = MenuBarPanelView()
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

        // Check timestamp and trigger auto-refresh if needed
        checkAndRefreshIfNeeded()
    }

    func closePopover() {
        popover?.performClose(nil)
        eventMonitor?.stop()
        eventMonitor = nil
    }

    // MARK: - SwiftUI Window Alternative Methods

    /// Toggle SwiftUI Window (alternative to NSPopover)
    /// This method can be called instead of showPopover()/closePopover()
    func toggleSwiftUIWindow() {
        print("🎯 [AppDelegate] toggleSwiftUIWindow called")
        guard let windowManager = windowManager,
              let button = statusItem?.button else {
            print("⚠️ [AppDelegate] Missing windowManager or button")
            return
        }

        print("📊 [AppDelegate] Current state - isWindowVisible: \(windowManager.isWindowVisible)")

        if windowManager.isWindowVisible {
            print("🔽 [AppDelegate] Window is visible, closing...")
            // Close window
            windowManager.hideWindow()
            eventMonitor?.stop()
            eventMonitor = nil
        } else {
            print("🔼 [AppDelegate] Window is hidden, opening...")
            // Calculate position and open window
            let position = windowManager.calculatePosition(from: button)
            print("📍 [AppDelegate] Calculated position: \(position)")

            // Activate app (required for proper focus behavior)
            NSApp.activate(ignoringOtherApps: true)
            print("⚡️ [AppDelegate] App activated")

            // Show window at calculated position
            windowManager.showWindow(at: position)

            // Start event monitor for click-outside detection
            eventMonitor = EventMonitor { [weak self] in
                self?.toggleSwiftUIWindow()
            }
            eventMonitor?.start()
            print("👀 [AppDelegate] Event monitor started")

            // Check timestamp and trigger auto-refresh if needed
            checkAndRefreshIfNeeded()
        }
    }

    private func checkAndRefreshIfNeeded() {
        let now = Date()
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60

        // Get last popover open timestamp
        let lastTimestamp = UserDefaults.standard.object(forKey: lastPopoverOpenKey) as? Date

        // Check if we need to refresh (no previous timestamp or > 2 hours)
        let shouldRefresh: Bool
        if let lastTimestamp = lastTimestamp {
            let timeSinceLastOpen = now.timeIntervalSince(lastTimestamp)
            shouldRefresh = timeSinceLastOpen > twoHoursInSeconds
            print("⏱️ Time since last popover open: \(Int(timeSinceLastOpen / 60)) minutes")
        } else {
            shouldRefresh = true
            print("⏱️ No previous popover open timestamp - triggering refresh")
        }

        // Update timestamp
        UserDefaults.standard.set(now, forKey: lastPopoverOpenKey)
        UserDefaults.standard.synchronize()

        // Trigger refresh if needed
        if shouldRefresh {
            print("🔄 Auto-refreshing data (last open > 2 hours ago)")
            Task {
                await bridgeManager.refreshAllData()
            }
        }
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
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        // window.backgroundColor = .clear  // Transparent background for glass effect
        window.isOpaque = false  // Allow transparency
        
//        window.standardWindowButton(.closeButton)?.isHidden = true
//        // Hide the miniaturize (minimize) button
//        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
//        // Hide the zoom button
//        window.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = AboutView_macOS(onClose: { [weak self] in
            guard let self = self else { return }
            if let window = self.aboutWindow {
                window.contentView = nil
                window.close()
            }
            self.aboutWindow = nil
        })

        window.contentView = NSHostingController(rootView: contentView).view

        // Set rounded corners on the window
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 24
            contentView.layer?.masksToBounds = true
        }

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
