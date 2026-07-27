# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Multi-platform Philips Hue controller with native watchOS and macOS apps. Core functionality shared through **HueDatShared** Swift package.

**App Store identity:** Ships as **Firefly**. All app targets share bundle ID `com.dtanquary.hue-dat` (universal purchase, one listing). The watch app is embedded in the iOS target ("Embed Watch Content" phase) but remains fully standalone (`WKRunsIndependentlyOfCompanionApp`) — installable from the watch App Store with no iPhone. There is no separate watch-container target.

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

# Build watchOS (Simulator) — use the generic destination; named watch-sim
# destinations fail to resolve now that the watch app declares a companion
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat Watch App" -destination 'generic/platform=watchOS Simulator' build

# Build macOS
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat macOS" -destination 'platform=macOS' build

# Build iOS (Simulator) — do NOT pass -sdk: it would override the SDK for the
# embedded watch-app dependency and break its WatchKit import
xcodebuild -project hue-dat.xcodeproj -scheme "hue dat iOS" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' build
```

**Build Scripts:** macOS target includes pre-build script to kill existing app instances (prevents duplicate menu bar icons during development). Debug-configuration only. The crash auto-relaunch signal handlers are likewise `#if DEBUG` — Release/App Store builds ship without them.

## Architecture

### Shared Package (HueDatShared)
- **Platform targets**: macOS 14.0+, watchOS 10.0+, iOS 18.0+
- **Contains**: Models, Services, Managers
- **Platform abstraction**: `DeviceIdentifierProvider` protocol for platform-specific device IDs

### Core Services

**1. BridgeDiscoveryService** - Network discovery
- mDNS-first: `NWBrowser` for `_hue._tcp` Bonjour, falls back to `https://discovery.meethue.com`
- iOS/watch Info.plists must keep `NSBonjourServices` + `NSLocalNetworkUsageDescription` for this
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

Models live in BridgeModels.swift, SSEEventModels.swift, HueDataModels.swift; search result types (SearchResults, SceneSearchResult) in Managers/SearchManager.swift — read the source for shapes.

**Gotcha**: HueRoom/HueZone/HueGroupedLight/HueLight custom Equatable compares ID + state only (efficient SwiftUI updates).

**Critical: Hue API v2 Device Hierarchy**
- Room/Zone `children` contain **device IDs**, NOT light IDs
- Correct flow: `deviceId` → `fetchDeviceDetails()` → find light service → `lightId` → `fetchLightDetails()`
- CANNOT query `/clip/v2/resource/light/{deviceId}` directly - will fail

### View Architecture

Views live in each target's `Views/` directory — read them for specifics. Non-obvious constraints:

**watchOS**
- RoomsAndZonesListView is the ONLY place automatic data loading occurs (via `.task`)
- Detail views: optimistic UI with rollback, 500ms debounce, control locking (mutual exclusion between power toggle & brightness), two-event haptic pattern (`.start` on begin, `.success`/`.failure` on completion)
- NO post-action refreshes — SSE handles real-time updates

**macOS** (menu bar app: AppKit AppDelegate + NSPopover, LSUIElement = YES, hidden from dock/Cmd+Tab)
- **CRITICAL**: NavigationStack toolbars and `.accessoryBar`/`.searchable` do NOT render/receive clicks inside an NSPopover — use PanelHeader + `.buttonStyle(.borderless)` + `headerButtonHover()` instead
- NSPopover supplies native glass — no extra panel-level material
- Popover height persisted via PopoverSizeManager; EventMonitor handles click-outside-to-dismiss

**iOS**
- ContentView skips the validation dialog when cached data exists (instant load); `isConnectionValidated` gates view transitions to prevent premature data loading
- GroupDetailView_iOS scene cards: tap activates, 0.5s long-press toggles pin

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

Reference implementations (reconnection, wake handling, staleness check, error preservation, per-platform comparison): load the `background-refresh` skill (`.claude/skills/background-refresh/SKILL.md`).

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

**API**: pin/unpin/toggle, query, and cleanup methods live in BridgeManager.swift (search "pinScene"). All are local-only (no network) and no-op when no bridge is connected; `@Published pinnedSceneIds` drives SwiftUI updates. Pins load on init, clear on disconnect, and are validated/cleaned after fetchScenes().

**UI status**: iOS ✅ (0.5s long-press toggles pin — GroupDetailView_iOS.swift) · macOS ✅ (right-click context menu, pinned scenes sort first — GroupDetailView_macOS.swift) · watchOS ⏳ not implemented

