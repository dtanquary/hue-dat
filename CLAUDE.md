# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Multi-platform Philips Hue controller with native watchOS and macOS apps. Core functionality shared through **HueDatShared** Swift package.

**Platforms:**
- **watchOS**: Standalone app with Digital Crown, haptic feedback, small-screen UI
- **macOS**: Menu bar app with floating panel (320×480pt)

## Build Commands

```bash
# Open project
open "hue dat.xcodeproj"

# Build watchOS (Simulator)
xcodebuild -project "hue dat.xcodeproj" -scheme "hue dat Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build

# Build macOS
xcodebuild -project "hue dat.xcodeproj" -scheme "hue dat macOS" -destination 'platform=macOS' build
```

**Build Scripts:** macOS target includes pre-build script to kill existing app instances (prevents duplicate menu bar icons during development).

## Architecture

### Shared Package (HueDatShared)
- **Platform targets**: macOS 14.0+, watchOS 10.0+
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
- **UserDefaults keys**: "ConnectedBridge", "cachedRooms", "cachedZones", "cachedScenes"
- **60-second auto-refresh**: Lifecycle-aware (stops in background)
- **Smart updates**: Only changes modified items (prevents UI flicker)
- **SSE processing**: Subscribes to event stream, maintains ID mapping dictionaries
- **Demo mode**: Offline testing with cached/hardcoded data
- **Utilities**: Color conversion (XY→RGB, mirek→RGB), scene filtering

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
- SSE lifecycle: starts on popover open, stops on blur

**MenuBarPanelView** - Main container
- Shows RoomsZonesListView_macOS when connected
- Bridge setup & about dialogs

**Detail Views** (macOS)
- RoomDetailView_macOS, ZoneDetailView_macOS
- Mouse/trackpad optimized
- Calls `refreshRoom(roomId:)` after scene activation

**SSEStatusIndicator** - Connection status
- Color-coded: green/blue/red/gray
- Subscribes to `streamStateSubject`

### State Management
- **MainActor**: BridgeManager, BridgeDiscoveryService
- **Actor**: HueAPIService (thread-safe)
- **Combine**: Publishers for reactive updates
- **Task Detachment**: JSON decoding off MainActor

## Critical Implementation Details

### Device Identification
- **watchOS**: `WKInterfaceDevice.current().identifierForVendor`
- **macOS**: IOKit hardware UUID with UserDefaults fallback
- Format: `hue_dat_watch_app#A1B2C3D4` (first 8 chars of UUID)

### SSL Certificate Handling
Uses `InsecureURLSessionDelegate` to accept self-signed certs from bridges. **Do not remove** unless implementing proper certificate pinning.

### Rate Limiting
- **HueAPIService**: 1-second minimum between grouped light commands
- **View debouncing**: 500ms in RoomDetailView/ZoneDetailView
- **Why**: Prevents overwhelming bridge, which becomes unresponsive

### Link Button Flow
1. First registration attempt → error type 101
2. User presses physical button
3. Retry succeeds, returns credentials

### Data Refresh Strategy
- **Auto**: 60-second timer (lifecycle-aware)
- **Manual**: Toolbar button, initial load
- **Smart updates**: Only modifies changed items
- **NO refreshes after control actions** (SSE handles real-time)

### SSE Architecture
- **Lifecycle-aware**: Starts on app active, stops on background
- **Event processing**: Filters relevant events, updates local state
- **Auto-reconnection**: Exponential backoff, max 5 attempts
- **Benefits**: Instant updates from physical switches/other apps

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
        └── BridgeManager.swift            # State & persistence

hue dat Watch App/                         # watchOS Target
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

hue dat macOS/                             # macOS Target
├── HueDatMacApp.swift                    # AppKit menu bar
├── EventMonitor.swift
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
```

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
