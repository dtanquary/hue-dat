//
//  HueDatMacApp.swift
//  hue dat macOS
//
//  macOS MenuBar app entry point
//

import SwiftUI
import HueDatShared
import AppKit

@main
struct HueDatMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
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

    // Strong references to prevent premature deallocation
    var hostingController: NSHostingController<AnyView>?
    var popoverEnvironment: PopoverEnvironment?

    // Re-entrancy guard for closePopover (prevents crash from simultaneous close triggers)
    private var isClosingPopover = false

    // UserDefaults key for tracking popover open timestamps
    private let lastPopoverOpenKey = "LastPopoverOpenTimestamp"

    // Wake from sleep tracking
    private var lastWakeTimestamp: Date?
    private let minimumDelayAfterWake: TimeInterval = 3.0  // 3 seconds

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize debug logger FIRST, then install crash handlers
        debugLog("🚀 applicationDidFinishLaunching - starting up")
        debugLog("Log file: \(DebugLogger.shared.logFilePath)")
        debugLog("Previous log: \(DebugLogger.shared.previousLogFilePath)")
        DebugLogger.shared.installCrashHandlers()
        DebugLogger.shared.installExceptionHandler()

        // Initialize bridge manager on main thread
        bridgeManager = BridgeManager()

        // Apply saved launch at login preference
        LaunchAtLoginManager.shared.applySavedPreference()

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

        // Observe wake from sleep notifications
        observeWakeNotifications()
    }

    func setupPopover() {
        debugLog("📦 setupPopover() - creating NSPopover")
        let popover = NSPopover()
        debugLog("📦 setupPopover() - getting content size from PopoverSizeManager")
        popover.contentSize = PopoverSizeManager.shared.contentSize
        popover.behavior = .transient
        self.popover = popover
        debugLog("📦 setupPopover() - popover created with size: \(popover.contentSize)")
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
        guard let popover = popover, let button = statusItem?.button else {
            debugLog("⚠️ showPopover() - early return: popover=\(self.popover != nil), button=\(statusItem?.button != nil)")
            return
        }

        debugLog("🚀 showPopover() - creating content view")

        // Store popover environment as property to prevent premature deallocation
        debugLog("🚀 showPopover() - creating PopoverEnvironment")
        popoverEnvironment = PopoverEnvironment(popover: popover)
        debugLog("🚀 showPopover() - PopoverEnvironment created")

        // Recreate content view controller for fresh material rendering
        debugLog("🚀 showPopover() - creating MenuBarPanelView")
        let contentView = MenuBarPanelView()
            .environment(bridgeManager)
            .environment(popoverEnvironment!)

        // Store hosting controller as property to ensure it stays alive
        debugLog("🚀 showPopover() - creating NSHostingController")
        hostingController = NSHostingController(rootView: AnyView(contentView))

        // Set preferred size BEFORE assigning to popover — otherwise NSPopover
        // adopts the hosting controller's intrinsic size (from SwiftUI frame modifiers),
        // discarding the user's saved height.
        let savedSize = PopoverSizeManager.shared.contentSize
        hostingController!.preferredContentSize = savedSize
        popover.contentSize = savedSize
        popover.contentViewController = hostingController
        debugLog("🚀 showPopover() - NSHostingController created and assigned with saved size: \(savedSize)")

        // Critical: Activate app to ensure transient behavior works
        debugLog("🚀 showPopover() - activating app")
        NSApp.activate()

        // Show popover
        debugLog("🚀 showPopover() - calling popover.show()")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        debugLog("🚀 showPopover() - popover.show() completed")

        // Explicitly ensure popover window gets keyboard focus
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.makeKey()
            debugLog("🚀 showPopover() - popover window made key")
        }

        // Start event monitor to catch outside clicks
        debugLog("🚀 showPopover() - creating EventMonitor")
        eventMonitor = EventMonitor { [weak self] in
            debugLogSync("👁️ EventMonitor handler called - will close popover")
            self?.closePopover()
        }
        eventMonitor?.start()
        debugLog("🚀 showPopover() - EventMonitor started")

        // Check timestamp and trigger auto-refresh if needed
        debugLog("🚀 showPopover() - calling checkAndRefreshIfNeeded()")
        checkAndRefreshIfNeeded()
        debugLog("🚀 showPopover() - complete")
    }

    func closePopover() {
        // Re-entrancy guard: performClose can synchronously trigger applicationWillResignActive,
        // which calls closePopover again. Without this guard, the re-entrant call deallocates
        // the hosting controller while the popover's own teardown is still in progress → crash.
        guard !isClosingPopover else {
            debugLogSync("🔻 closePopover() skipped - already closing (re-entrancy guard)")
            return
        }
        isClosingPopover = true

        debugLogSync("🔻 Starting popover close sequence")
        debugLogSync("🔻 popover.isShown: \(popover?.isShown ?? false)")

        // Stop event monitor BEFORE closing popover to prevent the monitor
        // from firing during the close and triggering another close attempt
        eventMonitor?.stop()
        eventMonitor = nil

        // Close the popover - this may synchronously trigger applicationWillResignActive
        if popover?.isShown == true {
            popover?.performClose(nil)
        }

        // Detach the content view controller from the popover before releasing our references.
        // This prevents the popover's internal teardown from racing with our deallocation.
        popover?.contentViewController = nil

        // Defer cleanup of SwiftUI hosting controller and environment to the next run loop
        // iteration, ensuring the popover's window animation and teardown complete first.
        let hc = hostingController
        let pe = popoverEnvironment
        hostingController = nil
        popoverEnvironment = nil
        DispatchQueue.main.async {
            // These references are captured solely to extend their lifetime past the
            // popover's close animation. They are released here after teardown completes.
            _ = hc
            _ = pe
        }

        isClosingPopover = false
        debugLogSync("🔻 Popover close sequence finished")
    }

    private func checkAndRefreshIfNeeded() {
        let now = Date()
        let thirtyMinutesInSeconds: TimeInterval = 30 * 60

        // Check if we just woke from sleep - add delay before allowing refresh
        if let lastWake = lastWakeTimestamp {
            let timeSinceWake = now.timeIntervalSince(lastWake)
            if timeSinceWake < minimumDelayAfterWake {
                debugLog("⏱️ Just woke from sleep \(String(format: "%.1f", timeSinceWake))s ago - delaying auto-refresh")

                // Schedule refresh after delay
                let remainingDelay = minimumDelayAfterWake - timeSinceWake
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
                    await performConnectionValidationAndRefresh()
                }
                return
            }
        }

        // Get last popover open timestamp
        let lastTimestamp = UserDefaults.standard.object(forKey: lastPopoverOpenKey) as? Date

        // Check if we need to refresh (no previous timestamp or > 30 minutes)
        let shouldRefresh: Bool
        if let lastTimestamp = lastTimestamp {
            let timeSinceLastOpen = now.timeIntervalSince(lastTimestamp)
            shouldRefresh = timeSinceLastOpen > thirtyMinutesInSeconds
            debugLog("⏱️ Time since last popover open: \(Int(timeSinceLastOpen / 60)) minutes")
        } else {
            shouldRefresh = true
            debugLog("⏱️ No previous popover open timestamp - triggering refresh")
        }

        // Update timestamp
        UserDefaults.standard.set(now, forKey: lastPopoverOpenKey)

        // Trigger refresh if needed (with validation)
        if shouldRefresh {
            debugLog("🔄 Auto-refreshing data (last open > 30 minutes ago)")
            Task {
                await performConnectionValidationAndRefresh()
            }
        }
    }

    /// Validate connection before performing auto-refresh
    /// This ensures the network is ready and the bridge is reachable
    private func performConnectionValidationAndRefresh() async {
        guard bridgeManager.isConnected else {
            debugLog("⚠️ No bridge connected - skipping auto-refresh")
            return
        }

        debugLog("🔍 Validating connection before auto-refresh...")

        // Validate connection with timeout
        await withTimeout(seconds: 3.0) { [self] in
            await self.bridgeManager.validateConnection()
        }

        guard bridgeManager.isConnectionValidated else {
            debugLog("❌ Connection validation failed - not performing auto-refresh")
            debugLog("💡 User can manually refresh when network is ready")
            return
        }

        debugLog("✅ Connection validated - proceeding with auto-refresh")
        await bridgeManager.refreshAllData(forceRefresh: false)
    }

    /// Execute an async operation with a timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            // Start the actual operation
            group.addTask {
                return await operation()
            }

            // Start timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            // Return first completed result
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    // MARK: - App State Monitoring

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("🛑 App terminating - cleaning up SSE stream")
        Task {
            await stopSSEStream()
        }
        // Connection observation cleanup handled automatically via task cancellation
    }

    func applicationWillResignActive(_ notification: Notification) {
        // Only close if the popover is actually shown. This method fires frequently
        // for menu bar apps (LSUIElement) and can fire re-entrantly during popover close.
        guard popover?.isShown == true else { return }
        debugLogSync("⚡️ App losing focus while popover shown - triggering closePopover()")
        closePopover()
        debugLogSync("⚡️ closePopover() completed")
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
        // If window already exists and is visible, just bring it to front
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        // Clean up any existing window properly
        if let existingWindow = aboutWindow {
            existingWindow.contentView = nil
            existingWindow.close()
            aboutWindow = nil
        }
        
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover // Or other materials like .sidebar, .headerView
        visualEffectView.blendingMode = .behindWindow // Or .withinWindow
        visualEffectView.state = .active // Or .inactive, .followsWindowActiveState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 230),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear  // Transparent background for glass effect
        window.isOpaque = false  // Allow transparency

        let contentView = AboutView_macOS(onClose: { [weak self] in
            guard let self = self else { return }
            if let window = self.aboutWindow {
                window.contentView = nil
                window.close()
            }
            self.aboutWindow = nil
        })

        // Create hosting controller and embed it in the visual effect view
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = visualEffectView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(hostingController.view)

        // Set the visual effect view as the window's content view
        window.contentView = visualEffectView

        // Set rounded corners on the visual effect view
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 24
        visualEffectView.layer?.masksToBounds = true

        self.aboutWindow = window

        // Center after content is laid out
        DispatchQueue.main.async {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    // MARK: - SSE Lifecycle Management

    // Connection observation is handled via withObservationTracking in observeConnectionChanges()
    private var isSSEStreamActive = false

    private func initializeSSEConnection() async {
        guard bridgeManager.isConnected else {
            debugLog("ℹ️ No bridge connected - skipping SSE initialization")
            return
        }

        debugLog("🔍 Initializing SSE connection on app launch...")

        // Validate connection to ensure HueAPIService is configured
        await bridgeManager.validateConnection()

        guard bridgeManager.isConnectionValidated else {
            debugLog("⚠️ Connection validation failed - not starting SSE")
            return
        }

        await startSSEStream()
    }

    private func observeConnectionChanges() {
        // Use withObservationTracking to observe connectedBridge changes
        func observe() {
            let bridge = withObservationTracking {
                self.bridgeManager.connectedBridge
            } onChange: {
                Task { @MainActor in
                    observe()
                }
            }
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
        observe()
    }

    private func observeWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWakeFromSleep() {
        debugLog("💤 System woke from sleep")
        lastWakeTimestamp = Date()

        // Clear connection validation state - connection may be stale
        bridgeManager.isConnectionValidated = false

        // Reconnect SSE stream after wake
        Task {
            await reconnectSSEAfterWake()
        }
    }

    private func reconnectSSEAfterWake() async {
        guard bridgeManager.isConnected else {
            debugLog("⚠️ No bridge connected - skipping SSE reconnect after wake")
            return
        }

        debugLog("🔄 Reconnecting SSE after wake from sleep...")

        // Stop existing SSE connection
        await stopSSEStream()

        // Wait a moment for network to stabilize
        try? await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))

        // Validate connection before reconnecting SSE
        await bridgeManager.validateConnection()

        guard bridgeManager.isConnectionValidated else {
            debugLog("❌ Connection validation failed after wake - not starting SSE")
            return
        }

        // Restart SSE stream
        await startSSEStream()
        debugLog("✅ SSE reconnected after wake from sleep")
    }

    private func handleConnectionEstablished() async {
        debugLog("🔗 Bridge connected - starting SSE stream...")
        await bridgeManager.validateConnection()

        guard bridgeManager.isConnectionValidated else {
            debugLog("⚠️ Connection validation failed")
            return
        }

        await startSSEStream()
    }

    private func handleConnectionLost() async {
        debugLog("🔌 Bridge disconnected - stopping SSE stream...")
        await stopSSEStream()
    }

    private func startSSEStream() async {
        // Prevent duplicate SSE streams
        if isSSEStreamActive {
            debugLog("⚠️ SSE stream already active - skipping duplicate start")
            return
        }

        debugLog("🟢 Starting background SSE stream and event listeners")

        // Start listening to SSE events in BridgeManager
        bridgeManager.startListeningToSSEEvents()

        // Start the actual SSE stream
        do {
            try await HueAPIService.shared.startEventStream()
            isSSEStreamActive = true
            debugLog("✅ Background SSE stream started successfully")
        } catch {
            debugLog("❌ Failed to start SSE stream: \(error.localizedDescription)")
            isSSEStreamActive = false
        }
    }

    private func stopSSEStream() async {
        guard isSSEStreamActive else {
            debugLog("ℹ️ SSE stream not active - nothing to stop")
            return
        }

        debugLog("🔴 Stopping background SSE stream and event listeners")

        // Stop listening to SSE events
        bridgeManager.stopListeningToSSEEvents()

        // Stop the SSE stream
        await HueAPIService.shared.stopEventStream()
        isSSEStreamActive = false
        debugLog("✅ Background SSE stream stopped")
    }
}
