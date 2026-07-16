---
name: background-refresh
description: Reference implementations for background refresh and SSE reconnection (the "gold standard" patterns from the macOS menu bar app). Use when implementing or modifying background refresh, SSE reconnection, app resume/wake handling, staleness checks, or auto-refresh behavior on any platform.
---

# Background Refresh & SSE Reconnection Patterns

The macOS menu bar app demonstrates the ideal background refresh and SSE reconnection patterns. All platforms should follow these principles. The core principles checklist lives in CLAUDE.md; this skill holds the reference implementations.

## Pattern 1: SSE Auto-Reconnection

**Trigger**: SSE stream disconnects (network loss, bridge reset, etc.)

```swift
// BridgeManager.swift - handleReconnection()
private func handleReconnection() async {
    // 1. Check if reconnection is appropriate
    guard connectedBridge != nil, !isDemoMode else { return }

    // 2. Calculate exponential backoff delay
    reconnectAttempts += 1
    let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 32.0)  // 1s, 2s, 4s... 32s max

    // 3. Sleep WITHOUT blocking MainActor (critical!)
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

    // 4. Verify bridge still connected (may have changed during sleep)
    guard connectedBridge != nil else { return }

    // 5. Attempt reconnection
    try await HueAPIService.shared.startEventStream()
    reconnectAttempts = 0  // Reset on success
}
```

**Key**: Called from `Task.detached { }` block to prevent UI freezes.

## Pattern 2: App Resume / Wake Handling

**Trigger**: App becomes active (iOS) or Mac wakes from sleep (macOS)

```swift
// Step 1: Invalidate connection state immediately
bridgeManager.isConnectionValidated = false

// Step 2: Stop existing SSE (may be stale)
await stopSSEStream()

// Step 3: Wait for network to stabilize (CRITICAL)
try? await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))

// Step 4: Validate connection with timeout
await withTimeout(seconds: 3.0) {
    await bridgeManager.validateConnection()
}

// Step 5: Only proceed if validation succeeded
guard bridgeManager.isConnectionValidated else {
    print("Connection validation failed - user can manually retry")
    return
}

// Step 6: Restart SSE stream
await startSSEStream()
```

## Pattern 3: Intelligent Auto-Refresh with Staleness Check

**Trigger**: View becomes visible (popover opens, tab selected, etc.)

**Key Insight**: Track when data was last refreshed. Skip refresh if data is still "fresh" (within threshold). This prevents unnecessary network calls and UI disruption on frequent wake/resume cycles.

```swift
private let lastPopoverOpenKey = "lastPopoverOpen"
private let minimumDelayAfterWake: TimeInterval = 3.0
private let refreshThreshold: TimeInterval = 1800  // 30 minutes

private func checkAndRefreshIfNeeded() {
    let now = Date()

    // Guard 1: Enforce minimum delay after resume/wake
    if let lastWake = lastWakeTimestamp {
        let timeSinceWake = now.timeIntervalSince(lastWake)
        if timeSinceWake < minimumDelayAfterWake {
            // Schedule delayed refresh instead
            Task {
                try? await Task.sleep(nanoseconds: UInt64((minimumDelayAfterWake - timeSinceWake) * 1_000_000_000))
                await performConnectionValidationAndRefresh()
            }
            return
        }
    }

    // Guard 2: STALENESS CHECK - Skip refresh if data is fresh
    let lastRefresh = UserDefaults.standard.object(forKey: lastPopoverOpenKey) as? Date
    let dataIsFresh = lastRefresh != nil && now.timeIntervalSince(lastRefresh!) < refreshThreshold

    if dataIsFresh {
        print("⏭️ Data is fresh (last refresh \(Int(now.timeIntervalSince(lastRefresh!) / 60)) min ago) - skipping auto-refresh")
        return  // No refresh needed!
    }

    // Update timestamp BEFORE refresh (prevents duplicate calls)
    UserDefaults.standard.set(now, forKey: lastPopoverOpenKey)

    // Guard 3: Validate connection before refresh
    print("🔄 Auto-refreshing data (last refresh > \(Int(refreshThreshold / 60)) minutes ago)")
    Task { await performConnectionValidationAndRefresh() }
}
```

**Why This Matters**: Without staleness checking, every app resume triggers a refresh, causing:
- Unnecessary API load on the bridge
- Potential UI flicker as data reloads
- Wasted battery on mobile devices

## Pattern 4: Data Preservation on Error

**Rule**: Never disrupt the user's view due to network issues.

```swift
// In refresh methods (getRooms, getZones, etc.)
do {
    let response = try await HueAPIService.shared.fetchRooms()
    // Success: update data
    self.rooms = enrichedRooms
    saveRoomsToStorage()
    refreshError = nil
} catch {
    // Failure: KEEP EXISTING DATA, just set error for optional display
    refreshError = "Error: \(error.localizedDescription)"
    // Do NOT clear self.rooms!
}
```

## Platform Comparison

| Behavior | macOS | iOS | watchOS |
|----------|-------|-----|---------|
| SSE runs in background | ✅ Always | ❌ Only when active | ❌ Only when active |
| Resume delay before refresh | 3s after wake | 3s after active | 3s after active |
| **Staleness check (skip if fresh)** | ✅ 30-min threshold | ✅ 30-min threshold | ✅ 30-min threshold |
| Refresh trigger | Popover open (lazy) | Pull-to-refresh + 60s timer | Manual button + 60s timer |
| Connection validation | Before every SSE/refresh | Before SSE restart | Before SSE restart |
| Data preserved on error | ✅ Yes | ✅ Yes | ✅ Yes |
| Timestamp tracking | ✅ UserDefaults | ✅ UserDefaults | ✅ UserDefaults |

## Implementation Files

- **macOS AppDelegate**: `hue-dat-macOS/HueDatMacApp.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterWake)
- **iOS ContentView**: `hue-dat-iOS/ContentView.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterResume)
- **watchOS ContentView**: `hue-dat-Watch-App/ContentView.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterResume)
- **BridgeManager reconnection**: `HueDatShared/.../BridgeManager.swift` (handleReconnection)
- **HueAPIService SSE**: `HueDatShared/.../HueAPIService.swift` (startEventStream, stopEventStream)
