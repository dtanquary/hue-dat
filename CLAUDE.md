# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Multi-platform Philips Hue controller with native watchOS and macOS apps. Core functionality shared through **HueDatShared** Swift package.

**Platforms:**
- **watchOS**: Standalone app with Digital Crown, haptic feedback, small-screen UI
- **macOS**: Menu bar app with floating panel (320×480pt)
- **iOS**: iPhone app with touch-optimized UI

**SDK Version:** iOS 18 SDK (version 26)
- Includes built-in `glassEffect()` view modifier
- **DO NOT create custom glassEffect extensions** - already available in SDK

## Build Commands

```bash
# Open project
open hue-dat.xcodeproj

# Build watchOS (Simulator)
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build

# Build macOS
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat macOS" -destination 'platform=macOS' build

# Build iOS (Simulator)
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat iOS" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' build
```

**Build Scripts:** macOS target includes pre-build script to kill existing app instances (prevents duplicate menu bar icons during development).

## Architecture

### Shared Package (HueDatShared)
- **Platform targets**: macOS 14.0+, watchOS 10.0+, iOS 18.0+
- **Contains**: Models, Services, Managers
- **Platform abstraction**: `DeviceIdentifierProvider` protocol for platform-specific device IDs

### Core Services

**1. BridgeDiscoveryService** - Network discovery
- Uses `https://discovery.meethue.com` API (mDNS commented out)
- 15-minute caching strategy

**2. BridgeRegistrationService** - Bridge pairing
- Implements "press link button" workflow (error type 101 handling)
- Uses platform-specific `DeviceIdentifierProvider`
- Uses `InsecureURLSessionDelegate` for self-signed cert bypass

**3. HueAPIService** (Actor-based, thread-safe)
- **HTTP/2 Multiplexing**: Single URLSession for REST + SSE
- **REST Methods**: fetchRooms, fetchZones, fetchGroupedLights, fetchScenes, setPower, setBrightness, activateScene
- **Rate Limiting**: 1-second minimum between grouped light updates
- **SSE Streaming**: Real-time events from `/eventstream/clip/v2`
- **Publishers**: `streamStateSubject`, `eventPublisher` (Combine)
- **Timeouts**: Infinite for SSE, 10s for REST

**4. BridgeManager** (@MainActor) - State & persistence
- **UserDefaults keys**: "ConnectedBridge", "cachedRooms", "cachedZones", "cachedScenes", "PinnedScenes"
- **60-second auto-refresh**: Lifecycle-aware (stops in background)
- **Smart updates**: Only changes modified items (prevents UI flicker)
- **SSE processing**: Subscribes to event stream, maintains ID mapping dictionaries
- **Demo mode**: Offline testing with cached/hardcoded data
- **Utilities**: Color conversion (XY→RGB, mirek→RGB), scene filtering
- **Force refresh**: `forceRefresh: Bool` parameter bypasses 30s debounce (for manual user-initiated refreshes)
- **Scene pinning**: Bridge-specific favorites with order preservation (see Scene Pinning section)

**5. SearchManager** (@MainActor) - Fast in-memory search
- **Initialization**: `SearchManager(bridgeManager: bridgeManager)` - requires BridgeManager instance
- **Search methods**: `search(_:)`, `searchRooms(_:)`, `searchZones(_:)`, `searchScenes(_:)`
- **Matching**: Case-insensitive substring matching using `localizedCaseInsensitiveContains`
- **Scene context**: Returns `SceneSearchResult` with associated room/zone information
- **Performance**: < 10ms typical, O(n) complexity, no API calls
- **Empty queries**: Returns empty results (no data returned)
- **Utility methods**: `hasMatches(for:)`, `matchCount(for:)`
- **No singleton**: Must be instantiated with BridgeManager reference

### Data Models (HueDatShared/Models/)

**BridgeModels.swift:**
- Bridge info & connection state
- Scene models with metadata, actions, palette, status
- Error types

**SSEEventModels.swift:**
- SSE event wrappers with filtering helpers
- Resource types: light, grouped_light, room, zone, scene

**HueDataModels.swift:**
- HueRoom, HueZone, HueGroupedLight, HueLight (all Equatable/Hashable)
- Custom equality: compares ID + state only (efficient SwiftUI updates)

**SearchManager.swift (Models defined in Managers/):**
- **SearchResults**: Container with `rooms: [HueRoom]`, `zones: [HueZone]`, `scenes: [SceneSearchResult]`
  - `isEmpty: Bool` - True if no results
  - `totalCount: Int` - Total matches across all types
- **SceneSearchResult**: Scene with room/zone context
  - `scene: HueScene` - The matched scene
  - `associatedRoom: HueRoom?` - Parent room if applicable
  - `associatedZone: HueZone?` - Parent zone if applicable
  - `displayName: String` - Formatted as "Scene Name - Room Name"
  - `contextDescription: String?` - Formatted as "in Room Name"

**Critical: Hue API v2 Device Hierarchy**
- Room/Zone `children` contain **device IDs**, NOT light IDs
- Correct flow: `deviceId` → `fetchDeviceDetails()` → find light service → `lightId` → `fetchLightDetails()`
- CANNOT query `/clip/v2/resource/light/{deviceId}` directly - will fail

### View Architecture

#### watchOS Views

**ContentView** - Root lifecycle manager
- Handles connection validation, auto-refresh timer, SSE stream lifecycle
- Starts/stops refresh & SSE based on scene phase (battery conservation)

**MainMenuView** - Navigation hub
- Shows discovery UI when disconnected
- Auto-navigates to rooms/zones on validation success

**RoomsAndZonesListView** - Primary list
- ONLY place automatic data loading occurs (via `.task`)
- Manual refresh button, last update timestamp
- Status dots (green=on, gray=off)

**RoomDetailView / ZoneDetailView** - Control interface
- **ColorOrbsBackground**: Opacity tied to brightness (0-100%)
- **Digital Crown**: `.low` sensitivity, 0-100 range
- **Drag control**: Vertical gesture on 8pt-wide brightness bar
- **500ms debouncing**: Timer-based, prevents excessive API calls
- **Optimistic UI**: Immediate response, rollback on failure
- **Haptic system**: Two-event pattern (`.start` on begin, `.success`/`.failure` on completion)
- **Control locking**: Mutual exclusion between power toggle & brightness
- **NO post-action refreshes**: SSE handles real-time updates
- Scene picker with color carousel

**Other views:**
- ScenePickerView, SettingsView, BridgesListView, ManualBridgeEntryView

#### macOS Views

**HueDatMacApp** - Entry point with AppDelegate
- **NSApplicationDelegate**: Full AppKit control for menu bar
- **NSPopover**: 320×480pt panel with `.ultraThinMaterial`
- **EventMonitor**: Click-outside-to-dismiss detection
- **LSUIElement = YES**: Hidden from dock/Cmd+Tab
- **SSE lifecycle**: Runs in background, auto-reconnects after wake from sleep
- **Wake-from-sleep handling**: Observes `NSWorkspace.didWakeNotification`, adds 3s delay before auto-refresh, validates connection before refresh

**MenuBarPanelView** - Main container
- Shows RoomsZonesListView_macOS when connected
- Bridge setup & about dialogs

**Detail Views** (macOS)
- RoomDetailView_macOS, ZoneDetailView_macOS
- Mouse/trackpad optimized
- Scene activation uses optimistic UI updates
- Optional SSE-aware refresh: `activateSceneWithConditionalRefresh()` only refreshes when SSE disconnected

**SSEStatusIndicator** - Connection status
- Color-coded: green/blue/red/gray
- Subscribes to `streamStateSubject`

#### iOS Views

**HueDatiOSApp** - Entry point
- SwiftUI App lifecycle
- Initializes BridgeManager and ContentView

**ContentView** - Root lifecycle manager
- **Smart startup**: Skips validation dialog if cached data exists (instant app load)
- **Validation gating**: Shows loading only when bridge exists and no cached data
- **isConnectionValidated**: Gates view transition to prevent premature data loading
- **SSE lifecycle**: Manages reconnection after app resume
- **Scene phase handling**: Stops SSE/refresh on background, restarts on active
- **1s network delay**: Waits for network stabilization after app resume
- **Background validation**: Validates bridge in background even when cached data shown

**MainMenuView_iOS** - Bridge discovery
- **Video background**: Looping light.mp4 with ambient audio mixing
- **Animated search**: Rotating icon during bridge discovery
- **Sheet presentations**: BridgesList, ManualEntry, Registration flows
- **LoopingVideoPlayer**: AVPlayerLooper with scene phase lifecycle

**RoomsAndZonesListView_iOS** - Primary data view
- **Multi-step loading**: LoadingStepIndicator with progress tracking
- **TaskGroup-based loading**: Parallel fetch with completion tracking
- **Loading states**: Step 1-4 with descriptive messages (Preparing, Loading rooms, Loading zones, Loading scenes)
- **Pull-to-refresh**: Integrated refresh control
- **SSE status indicator**: Real-time connection monitoring
- **Turn off all lights**: Bulk control with separate loading state
- **Section headers**: Room/zone counts with status dots
- **Search bar**: Bottom search using `.safeAreaInset(edge: .bottom)` (NOT toolbar - see Known Issues)

**RoomDetailView_iOS / ZoneDetailView_iOS** - Control interfaces
- **Touch-optimized**: Slider controls for brightness (0-100%)
- **Scene grid**: 2-column LazyVGrid with scene cards
- **Scene card gestures**:
  - **Tap**: Activates scene (quick press)
  - **Long press (0.5s)**: Toggles pin with haptic feedback
- **Pin indicators**: White pin icon (top-left) + active checkmark (top-right)
- **ColorOrbsBackground**: Opacity tied to brightness
- **Optimistic UI**: Immediate visual feedback
- **500ms debouncing**: Prevents excessive API calls
- **Turn off button**: Per-room/zone power control
- **Scene pinning**: Fully functional via long-press gesture

**LoadingStepIndicator** - Multi-step progress component (NEW)
- **Visual step dots**: Animated circles showing progress
- **Step counter**: "Step X of Y" display
- **Descriptive messages**: Context-aware loading text
- **Smooth animations**: Spring effects on dot transitions
- **.regularMaterial**: Native iOS glass effect background

**Other views:**
- RoomRowView, ZoneRowView - List row components
- BridgesListView_iOS - Discovered bridges with registration
- ManualBridgeEntryView_iOS - Manual IP entry
- SettingsView_iOS - App configuration
- SSEStatusIndicator - Connection status (shared with macOS)

### State Management
- **MainActor**: BridgeManager, BridgeDiscoveryService
- **Actor**: HueAPIService (thread-safe)
- **Combine**: Publishers for reactive updates
- **Task Detachment**: JSON decoding off MainActor

## Critical Implementation Details

### Device Identification
- **watchOS**: `WKInterfaceDevice.current().identifierForVendor`
- **macOS**: IOKit hardware UUID with UserDefaults fallback
- **iOS**: `UIDevice.current.identifierForVendor`
- Format: `hue_dat_watch_app#A1B2C3D4` (first 8 chars of UUID)

### SSL Certificate Handling
Uses `InsecureURLSessionDelegate` to accept self-signed certs from bridges. **Do not remove** unless implementing proper certificate pinning.

### Rate Limiting & Debouncing
- **HueAPIService**:
  - 1-second throttle between brightness updates (non-blocking, drops rapid calls)
  - Power toggles (setPower) exempt from rate limiting (immediate execution)
- **View debouncing**: 500ms in RoomDetailView/ZoneDetailView
- **Refresh debouncing**: 30s between auto-refresh calls (bypass with `forceRefresh: true`)
- **Connection validation**: 3s timeout for validation calls
- **Why**: Prevents overwhelming bridge, which becomes unresponsive

### Link Button Flow
1. First registration attempt → error type 101
2. User presses physical button
3. Retry succeeds, returns credentials

### Data Refresh Strategy
- **Auto**: 60-second timer (lifecycle-aware), respects 30s debounce
- **Manual**: Toolbar button with `forceRefresh: true` (bypasses debounce)
- **Smart updates**: Only modifies changed items (prevents UI flicker)
- **NO refreshes after control actions** (SSE handles real-time)
- **macOS wake handling**: 3s delay + connection validation before auto-refresh
- **Loading states**: Always reset properly, even on timeout/error

### SSE Architecture
- **Lifecycle-aware**: Starts on app active, stops on background
- **Event processing**: Filters relevant events, updates local state
- **Auto-reconnection**: Exponential backoff (1s, 2s, 4s, 8s, 16s, 32s max), max 5 attempts
- **Non-blocking reconnection**: Uses `Task.detached` to prevent UI freezes during reconnection delays
- **Network error handling**: Special handling for `NSURLErrorNetworkConnectionLost` (connection reset by peer)
- **Wake-from-sleep** (macOS): Auto-reconnects after Mac wakes (1s delay + connection validation)
- **App resume** (iOS): Auto-reconnects after app becomes active (1s delay + connection validation)
- **Benefits**: Instant updates from physical switches/other apps

### Gold Standard: Background Refresh Architecture

The macOS menu bar app demonstrates the ideal background refresh and SSE reconnection patterns. **All platforms should follow these principles.**

**Reference Implementation:** `HueDatMacApp.swift` (AppDelegate)

#### Core Principles Checklist

When implementing background refresh on any platform, verify:

- [ ] **Non-blocking delays**: All reconnection delays use `Task.detached` (never block MainActor)
- [ ] **Validation-first**: Always validate connection before SSE restart or data refresh
- [ ] **Network stabilization**: Wait 3s after resume/wake before validation attempts
- [ ] **Staleness check**: Track last refresh timestamp; skip refresh if data is "fresh" (< threshold)
- [ ] **Preserve existing data**: Never clear UI data on refresh failure
- [ ] **Lazy refresh triggers**: Only refresh when view is actively displayed
- [ ] **No post-action refreshes**: Rely on SSE for real-time updates after user actions
- [ ] **Graceful timeout**: Use 3s timeout on validation to prevent hanging

#### Pattern 1: SSE Auto-Reconnection

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

#### Pattern 2: App Resume / Wake Handling

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

#### Pattern 3: Intelligent Auto-Refresh with Staleness Check

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

#### Pattern 4: Data Preservation on Error

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

#### Platform Comparison

| Behavior | macOS | iOS | watchOS |
|----------|-------|-----|---------|
| SSE runs in background | ✅ Always | ❌ Only when active | ❌ Only when active |
| Resume delay before refresh | 3s after wake | 3s after active | 3s after active |
| **Staleness check (skip if fresh)** | ✅ 30-min threshold | ✅ 30-min threshold | ✅ 30-min threshold |
| Refresh trigger | Popover open (lazy) | Pull-to-refresh + 60s timer | Manual button + 60s timer |
| Connection validation | Before every SSE/refresh | Before SSE restart | Before SSE restart |
| Data preserved on error | ✅ Yes | ✅ Yes | ✅ Yes |
| Timestamp tracking | ✅ UserDefaults | ✅ UserDefaults | ✅ UserDefaults |

#### Implementation Files

- **macOS AppDelegate**: `hue-dat-macOS/HueDatMacApp.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterWake)
- **iOS ContentView**: `hue-dat-iOS/ContentView.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterResume)
- **watchOS ContentView**: `hue-dat-Watch-App/ContentView.swift` (checkAndRefreshIfNeeded, reconnectSSEAfterResume)
- **BridgeManager reconnection**: `HueDatShared/.../BridgeManager.swift` (handleReconnection)
- **HueAPIService SSE**: `HueDatShared/.../HueAPIService.swift` (startEventStream, stopEventStream)

### Digital Crown Debouncing (CRITICAL)
- **500ms timer-based debouncing**: API call only after user stops adjusting
- **Why**: Rapid crown rotation can generate 100+ API calls without debouncing
- **Optimistic UI**: Immediate visual feedback, rollback on failure
- **Haptic timing**: Initial `.start`, final `.success` after first network completion
- **Session-based reset**: `hasGivenFinalBrightnessHaptic` resets on new session

### Demo Mode
- Enable: `BridgeManager.shared.enableDemoMode()`
- Bypasses all network calls, uses cached/hardcoded data
- SSE disabled, changes don't persist

### Scene Pinning
**Feature**: Users can "pin" favorite scenes for quick access in each room/zone.

**Storage Strategy:**
- **UserDefaults key**: `"PinnedScenes"`
- **Data structure**: `[String: [String: [String]]]` (bridge ID → group ID → scene IDs array)
- **Order preservation**: Arrays maintain insertion order for UI display
- **Bridge-specific**: Each bridge has independent pin lists (cleared on disconnect)
- **Auto-cleanup**: Stale pins (for deleted scenes) removed during `fetchScenes()` with console logging

**Core API Methods** (BridgeManager.swift:1646-1850):
```swift
// Pin/unpin operations
pinScene(sceneId:forGroupId:)           // Add scene to favorites
unpinScene(sceneId:forGroupId:)         // Remove from favorites
toggleScenePin(sceneId:forGroupId:)     // Toggle pin state

// Query methods
isScenePinned(sceneId:forGroupId:) -> Bool
getPinnedScenes(forRoomId:) -> [HueScene]     // Returns scenes in pinned order
getPinnedScenes(forZoneId:) -> [HueScene]     // Returns scenes in pinned order
getPinnedSceneCount(forGroupId:) -> Int

// Cleanup methods
clearPinnedScenes(forGroupId:)          // Clear pins for specific room/zone
clearAllPinnedScenes()                  // Clear all pins across all bridges
```

**Implementation Notes:**
- All methods use `connectedBridge?.bridge.id` - if no bridge connected, operations are no-ops
- Published property `pinnedSceneIds` triggers SwiftUI updates automatically
- Storage methods: `loadPinnedScenesFromStorage()`, `savePinnedScenesToStorage()`, `validateAndCleanPinnedScenes()`
- Lifecycle integration: Loads on init, clears on disconnect, validates after fetchScenes()
- No network calls - all operations are local-only

**UI Implementation Status:**
- **iOS**: ✅ Fully implemented
  - Long-press gesture (0.5s minimum) to toggle pin
  - White pin icon in top-left corner of scene cards
  - Medium haptic feedback on pin/unpin
  - Tap vs long-press differentiation via gesture handlers
  - Files: RoomDetailView_iOS.swift, ZoneDetailView_iOS.swift
- **watchOS**: ⏳ Not yet implemented
- **macOS**: ⏳ Not yet implemented

**iOS Gesture Implementation:**
```swift
ZStack { /* scene card content */ }
    .contentShape(Rectangle())
    .onTapGesture { activateScene(scene) }           // Quick tap activates
    .onLongPressGesture(minimumDuration: 0.5) {      // Long press pins
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        bridgeManager.toggleScenePin(sceneId: scene.id, forGroupId: groupId)
    }
```

**Future Enhancements:**
- Dedicated "Pinned Scenes" sections in list views
- Drag-to-reorder pinned scenes (arrays preserve insertion order)
- Context menu integration (alternative to long-press)

## File Organization

```
HueDatShared/                              # Shared Package
├── Package.swift
└── Sources/HueDatShared/
    ├── Models/
    │   ├── BridgeModels.swift            # Connection, scenes, errors
    │   ├── SSEEventModels.swift          # Real-time events
    │   └── HueDataModels.swift           # Rooms, zones, lights
    ├── Services/
    │   ├── DeviceIdentifierProvider.swift
    │   ├── BridgeDiscoveryService.swift
    │   ├── BridgeRegistrationService.swift
    │   ├── HueAPIService.swift           # Actor-based API + SSE
    │   └── InsecureURLSessionDelegate.swift
    └── Managers/
        ├── BridgeManager.swift            # State & persistence
        └── SearchManager.swift            # In-memory search

hue-dat-Watch-App/                         # watchOS Target
├── hue_datApp.swift
├── ContentView.swift                      # Lifecycle manager
├── DeviceIdentifierProvider_watchOS.swift
└── Views/
    ├── MainMenuView.swift
    ├── RoomsAndZonesListView.swift
    ├── RoomDetailView.swift              # Crown + haptics
    ├── ZoneDetailView.swift
    ├── ColorOrbsBackground.swift
    ├── ScenePickerView.swift
    ├── SettingsView.swift
    ├── BridgesListView.swift
    └── ManualBridgeEntryView.swift

hue-dat-macOS/                             # macOS Target
├── HueDatMacApp.swift                    # AppKit menu bar
├── EventMonitor.swift
├── LaunchAtLoginManager.swift            # Startup configuration
├── DeviceIdentifierProvider_macOS.swift
├── Extensions/
│   └── ViewExtensions.swift              # glassEffect()
└── Views/
    ├── MenuBarPanelView.swift
    ├── AboutView_macOS.swift
    ├── BridgeSetupView_macOS.swift
    ├── RoomsZonesListView_macOS.swift
    ├── RoomDetailView_macOS.swift
    ├── ZoneDetailView_macOS.swift
    ├── SettingsView_macOS.swift
    └── SSEStatusIndicator.swift

hue-dat-iOS/                               # iOS Target
├── HueDatiOSApp.swift                    # SwiftUI App entry
├── ContentView.swift                      # Lifecycle manager + SSE
├── DeviceIdentifierProvider_iOS.swift
├── Assets.xcassets/                       # App icons
└── Views/
    ├── MainMenuView_iOS.swift             # Bridge discovery + video
    ├── RoomsAndZonesListView_iOS.swift    # Primary data view + search
    ├── RoomDetailView_iOS.swift           # Touch controls
    ├── ZoneDetailView_iOS.swift           # Touch controls
    ├── SearchResultsOverlay.swift         # Full-screen search results
    ├── HighlightedText.swift              # Search term highlighting
    ├── LoadingStepIndicator.swift         # Multi-step progress
    ├── LoopingVideoPlayer.swift           # Background video
    ├── ToastView.swift                    # Toast notifications
    ├── ColorOrbsBackground_iOS.swift      # Dynamic orbs
    ├── RoomRowView.swift                  # List row
    ├── ZoneRowView.swift                  # List row
    ├── BridgesListView_iOS.swift          # Discovery results
    ├── ManualBridgeEntryView_iOS.swift    # Manual IP entry
    ├── SettingsView_iOS.swift             # App settings
    └── SSEStatusIndicator.swift           # Connection status
```

## Search Functionality

### SearchManager Usage

**Initialization** (requires BridgeManager instance):
```swift
let searchManager = SearchManager(bridgeManager: bridgeManager)
```

**Basic search** (all types):
```swift
let results = searchManager.search("living")
// Returns SearchResults with rooms, zones, and scenes arrays
print("Found \(results.totalCount) matches")
```

**Type-specific searches:**
```swift
let rooms = searchManager.searchRooms("bed")       // [HueRoom]
let zones = searchManager.searchZones("down")      // [HueZone]
let scenes = searchManager.searchScenes("bright")  // [SceneSearchResult]
```

**Scene results with context:**
```swift
for sceneResult in scenes {
    print(sceneResult.displayName)           // "Bright - Living Room"
    print(sceneResult.contextDescription)     // "in Living Room"
    // Access scene: sceneResult.scene
    // Access room: sceneResult.associatedRoom
}
```

**Utility methods:**
```swift
if searchManager.hasMatches(for: "kitchen") {
    // Show results UI
}

let count = searchManager.matchCount(for: "office")
```

**Important Notes:**
- Empty queries return empty results
- Case-insensitive substring matching
- Scenes without room/zone context are excluded
- No API calls - all in-memory (< 10ms)
- Works with cached data in demo mode

## API Integration

### Endpoints

**Discovery & Registration (v1):**
- `GET https://discovery.meethue.com`
- `POST https://{bridge-ip}/api`

**Control & Status (v2):**
- `GET /clip/v2/resource` - Validation
- `GET /clip/v2/resource/room[/{id}]`
- `GET /clip/v2/resource/zone[/{id}]`
- `GET /clip/v2/resource/grouped_light[/{id}]`
- `PUT /clip/v2/resource/grouped_light/{id}` - Control
- `GET /clip/v2/resource/scene`
- `PUT /clip/v2/resource/scene/{id}` - Activate

**SSE:**
- `GET /eventstream/clip/v2` (Accept: text/event-stream)

All v2 requests include `hue-application-key` header.

### Request Examples

**Registration:**
```json
{
  "devicetype": "hue_dat_watch_app#A1B2C3D4",
  "generateclientkey": true
}
```

**Light Control:**
```json
{
  "on": {"on": true},
  "dimming": {"brightness": 75.0}
}
```

**Error Response (Link Button):**
```json
[{
  "error": {
    "type": 101,
    "address": "/api",
    "description": "link button not pressed"
  }
}]
```
