# HueDat

Modern Philips Hue controller for watchOS, macOS, and iOS with native platform integration and real-time Server-Sent Events streaming.

## Overview

HueDat is a multi-platform Swift application providing seamless control of Philips Hue lights through native watchOS, macOS, and iOS applications. Built with SwiftUI and modern Swift concurrency, it features real-time updates via SSE, optimistic UI updates, the Liquid Glass design language across all three platforms, and platform-specific optimizations including Digital Crown integration, a resizable macOS menu bar panel, and iOS touch-optimized controls.

## Features

### watchOS
- **Digital Crown Control** - Precise brightness adjustment with low sensitivity (0-100%)
- **Vertical Drag Gestures** - Alternative brightness control via 8pt-wide drag bar
- **Haptic Feedback** - Two-event tactile confirmation (start + success/failure)
- **Optimistic UI** - Immediate visual response with automatic rollback on failure
- **500ms Debouncing** - Prevents API spam during rapid Digital Crown rotation
- **Scene Selection** - Visual scene picker with color carousel
- **ColorOrbsBackground** - Dynamic background orbs with opacity tied to brightness
- **Battery Conservation** - Lifecycle-aware refresh that stops in background

### macOS
- **Menu Bar Integration** - Persistent menu bar app (hidden from dock)
- **Liquid Glass Panel** - 320pt-wide floating panel with native popover glass and drag-to-resize height (persisted)
- **Push Navigation** - NavigationStack with shared glass PanelHeader and working back button inside the NSPopover
- **Search** - Header search field filtering rooms, zones, and scenes with room/zone context
- **Click-Outside Dismissal** - Natural UX with global event monitoring
- **Scene Grid Cards** - Visual scene selection with instant feedback
- **Scene Pinning** - Right-click context menu to pin favorites; pinned scenes sort first
- **SSE Status Indicator** - Color-coded connection status (green/blue/red/gray)
- **Bulk Light Control** - Manage all lights in rooms/zones simultaneously
- **Launch at Login** - Optional startup configuration, self-heals to the /Applications copy on launch

<img width="349" height="650" alt="Screenshot 2026-04-26 at 6 13 27 AM" src="https://github.com/user-attachments/assets/ff7b03dd-4834-43d0-b43d-d538663a673f" />

### iOS
- **Liquid Glass Controls** - Glass brightness pill, power button, and slider over dynamic color orbs
- **Animated Bridge Discovery** - Rotating search icon during network discovery
- **Animated MeshGradient Background** - Slow-drifting Hue-ish colors on the main menu (light/dark palettes)
- **Touch-Optimized Controls** - Native slider controls for brightness adjustment
- **Native Search** - `.searchable` list with inline results and search term highlighting
- **Scene Grid** - Visual scene cards with tap activation
- **Scene Pinning** - Long-press to pin favorites with haptic feedback
- **Pull-to-Refresh** - Integrated gesture-based data refresh
- **Glass Loading Card** - Spinner + message overlay during parallel TaskGroup data fetch
- **SSE Status Indicator** - Real-time connection monitoring
- **Validation Gating** - Smart loading that prevents premature data fetches
- **Instant Main Menu** - Zero-delay display when no bridge configured
- **App Resume Handling** - Automatic SSE reconnection with network stabilization delay

### Shared Features
- **Real-time SSE Streaming** - Instant updates from physical switches and other apps
- **HTTP/2 Multiplexing** - Single URLSession for efficient REST + SSE communication
- **Smart Updates** - Only modifies changed items to prevent UI flicker
- **60-second Auto-refresh** - Background data updates with lifecycle awareness
- **Rate Limiting** - 1-second minimum between grouped light updates
- **Bridge Discovery** - Automatic discovery via `https://discovery.meethue.com`
- **In-Memory Search** - SearchManager with case-insensitive matching across rooms, zones, and scenes (< 10ms, no API calls)
- **Scene Pinning** - Bridge-specific favorites with order preservation and automatic stale-pin cleanup
- **Demo Mode** - Full offline testing capability with cached data
- **Caching** - UserDefaults persistence for rooms, zones, scenes, and connections

## Requirements

- **Xcode**: 26.0+ (tested with Xcode 26.1.1)
- **macOS**: 15.0+ (Sequoia)
- **watchOS**: 10.0+
- **iOS**: 18.0+ (iOS 18 SDK version 26)
- **Swift**: 5.0+
- **Hardware**: Philips Hue Bridge (v2 API compatible)

## Installation

### Clone Repository

```bash
git clone https://github.com/dtanquary/hue-dat.git
cd hue-dat
```

### Open in Xcode

```bash
open hue-dat.xcodeproj
```

### Build watchOS (Simulator)

```bash
xcodebuild -project hue-dat.xcodeproj \
  -scheme "hue dat Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  build
```

### Build macOS

```bash
xcodebuild -project hue-dat.xcodeproj \
  -scheme "hue dat macOS" \
  -destination 'platform=macOS' \
  build
```

### Build iOS (Simulator)

```bash
xcodebuild -project hue-dat.xcodeproj \
  -scheme "hue dat iOS" \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  build
```

## Architecture

### Shared Package (HueDatShared)

Core functionality is shared between platforms via a Swift Package Manager package supporting macOS 15.0+, watchOS 10.0+, and iOS 18.0+.

**Components:**

- **Models** - Equatable/Hashable data structures for bridges, rooms, zones, lights, scenes, and SSE events
- **Services** - Network layer with bridge discovery, registration, and API communication
- **Managers** - State management and persistence via UserDefaults

### Platform-Specific Targets

#### watchOS App
- Digital Crown and haptic integration
- Small-screen optimized SwiftUI views
- WatchKit device identification
- ContentView lifecycle manager for SSE and refresh control

#### macOS App
- AppKit menu bar integration with NSApplicationDelegate
- NSPopover-based floating panel (320pt wide, height resizable and persisted)
- NavigationStack push navigation with shared glass PanelHeader
- EventMonitor for click-outside detection
- IOKit hardware UUID for device identification
- LaunchAtLoginManager for startup configuration

#### iOS App
- SwiftUI App lifecycle with ContentView root manager
- Touch-optimized slider controls for brightness
- Glass LoadingCard overlay during parallel TaskGroup data fetch
- UIDevice.current.identifierForVendor for device identification
- Validation gating to prevent premature data loading
- App resume handling with network stabilization delay

### Actor-Based Concurrency

**HueAPIService** (Actor)
- Thread-safe API operations
- HTTP/2 multiplexing via single URLSession
- SSE streaming with auto-reconnection (exponential backoff, max 5 attempts)
- Infinite timeout for SSE, 10s for REST operations
- Rate limiting (1-second minimum between grouped light updates)

**BridgeManager** (@MainActor)
- UI state management
- 60-second auto-refresh timer
- Smart updates (only changes modified items)
- SSE event processing
- Demo mode support

## Project Structure

```
hue-dat/
├── HueDatShared/                          # Swift Package (shared code)
│   ├── Package.swift
│   └── Sources/HueDatShared/
│       ├── Models/
│       │   ├── BridgeModels.swift         # Connection, scenes, errors
│       │   ├── SSEEventModels.swift       # Real-time event types
│       │   └── HueDataModels.swift        # Rooms, zones, lights
│       ├── Services/
│       │   ├── DeviceIdentifierProvider.swift
│       │   ├── BridgeDiscoveryService.swift
│       │   ├── BridgeRegistrationService.swift
│       │   ├── HueAPIService.swift        # Actor-based API + SSE
│       │   └── InsecureURLSessionDelegate.swift
│       └── Managers/
│           ├── BridgeManager.swift        # State & persistence
│           ├── ScenePinningManager.swift  # Pinned scene favorites
│           ├── SearchManager.swift        # In-memory search
│           └── SSEEventProcessor.swift    # SSE event handling
│
├── hue-dat-Watch-App/                     # watchOS Target
│   ├── Views/
│   │   ├── ContentView.swift              # Lifecycle manager
│   │   ├── RoomDetailView.swift           # Digital Crown + haptics
│   │   ├── ColorOrbsBackground.swift      # Dynamic brightness orbs
│   │   └── [6 other views]
│   └── DeviceIdentifierProvider_watchOS.swift
│
├── hue-dat-macOS/                         # macOS Target
│   ├── HueDatMacApp.swift                # Menu bar + NSApplicationDelegate
│   ├── EventMonitor.swift                # Click-outside detection
│   ├── PopoverSizeManager.swift          # Popover height persistence
│   ├── LaunchAtLoginManager.swift        # Startup configuration
│   ├── Views/
│   │   ├── MenuBarPanelView.swift        # NavigationStack + routes
│   │   ├── PanelHeader.swift             # Shared glass header + back button
│   │   ├── RoomsZonesListView_macOS.swift # Primary list + search
│   │   ├── GroupDetailView_macOS.swift   # Unified room/zone detail + pinning
│   │   ├── PopoverResizeHandle.swift     # Drag-to-resize handle
│   │   ├── SSEStatusIndicator.swift      # Connection status
│   │   └── [5 other views]
│   └── DeviceIdentifierProvider_macOS.swift
│
└── hue-dat-iOS/                           # iOS Target
    ├── HueDatiOSApp.swift                # SwiftUI App entry
    ├── ContentView.swift                  # Lifecycle + SSE manager
    ├── DeviceIdentifierProvider_iOS.swift
    ├── Assets.xcassets/                   # App icons
    └── Views/
        ├── MainMenuView_iOS.swift         # Bridge discovery + MeshGradient
        ├── RoomsAndZonesListView_iOS.swift # Primary data view + search
        ├── GroupDetailView_iOS.swift      # Unified room/zone detail + pinning
        ├── GroupRowView_iOS.swift         # Unified room/zone list row
        ├── LoadingStepIndicator.swift     # Glass LoadingCard
        └── [8 other views]
```

## Technical Highlights

### Digital Crown Debouncing

**Problem**: Rapid Digital Crown rotation generates 100+ API calls without debouncing
**Solution**: 500ms timer-based debouncing with optimistic UI

- Visual feedback is immediate (0ms)
- API calls only fire after user stops adjusting (500ms idle)
- Haptic feedback: `.start` on begin, `.success` on network completion
- Session-based reset prevents stale haptic state

### SSE Architecture

**Real-time Updates** via `/eventstream/clip/v2`:

- Lifecycle-aware: starts on app active, stops on background
- Event filtering for relevant resources (lights, scenes, rooms, zones)
- Auto-reconnection with exponential backoff
- Benefits: Instant updates from physical switches and other apps

### HTTP/2 Multiplexing

Single URLSession handles both REST and SSE on separate streams:
- Efficient connection reuse
- Reduced latency for parallel requests
- Proper resource management

### Smart Update Strategy

**Auto-refresh**: 60-second timer (lifecycle-aware)
**Manual refresh**: Toolbar button, initial load
**SSE updates**: Real-time event processing
**Smart diffing**: Only modifies changed items

**Critical**: No refreshes after control actions - SSE handles real-time updates

### Rate Limiting

- **HueAPIService**: 1-second minimum between grouped light commands
- **View debouncing**: 500ms in detail views
- **Reason**: Prevents overwhelming bridge, which becomes unresponsive under load

### Liquid Glass Design Language

All three platforms adopt the SDK's built-in `glassEffect()` modifier:

- Glass brightness pill, power button, and slider over dynamic ColorOrbsBackground (iOS + macOS detail views)
- Shared glass PanelHeader on macOS (NavigationStack toolbars don't render inside an NSPopover)
- Glass LoadingCard overlay during parallel TaskGroup data fetch (iOS)
- **Validation gating**: Prevents showing loading when no bridge configured

## API Integration

### Philips Hue API v2

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

### SSL Certificate Handling

Uses `InsecureURLSessionDelegate` to accept self-signed certificates from Hue bridges. **Note**: For production use, consider implementing proper certificate pinning.

### Link Button Flow

1. First registration attempt → error type 101
2. User presses physical button on bridge
3. Retry succeeds, returns credentials
4. Credentials cached in UserDefaults

## Development

### Build Scripts

macOS target includes pre-build script to kill existing app instances, preventing duplicate menu bar icons during development.

### Demo Mode

Enable via `BridgeManager.shared.enableDemoMode()`:
- Bypasses all network calls
- Uses cached/hardcoded data
- SSE disabled
- Changes don't persist
- Useful for UI development and testing

### Device Hierarchy (Important)

Hue API v2 device hierarchy:
- Room/Zone `children` contain **device IDs**, not light IDs
- Correct flow: `deviceId` → `fetchDeviceDetails()` → find light service → `lightId` → `fetchLightDetails()`
- **Cannot** query `/clip/v2/resource/light/{deviceId}` directly - will fail

### Platform Abstraction

`DeviceIdentifierProvider` protocol enables platform-specific device identification:
- **watchOS**: `WKInterfaceDevice.current().identifierForVendor`
- **macOS**: IOKit hardware UUID with UserDefaults fallback
- **iOS**: `UIDevice.current.identifierForVendor`
- Format: `hue_dat_watch_app#A1B2C3D4` (first 8 chars of UUID)

## Contributing

Contributions are welcome! This project follows standard Swift/Xcode conventions.

### Setup for Contributors

1. **Bundle Identifiers**: The project uses `com.dtanquary.*` bundle IDs. You'll need to update these to your own identifier in Xcode's target settings (Signing & Capabilities) to build on physical devices.
2. **Development Team**: Set your own Apple Developer Team in each target's build settings.
3. **Philips Hue Bridge**: A physical Hue Bridge (v2 API compatible) is required for full testing. Use **Demo Mode** (`BridgeManager.shared.enableDemoMode()`) for UI development without hardware.
4. **SSL Certificates**: The app uses `InsecureURLSessionDelegate` to accept self-signed certificates from local Hue bridges. This is intentional and required for local network communication.

### Guidelines

- Follow existing code style (SwiftUI, actor-based concurrency)
- Test on all three platform targets (watchOS, macOS, iOS)
- Maintain platform abstraction via HueDatShared package
- Update CLAUDE.md if adding new architectural patterns
- Ensure iOS-specific features use touch-optimized controls

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Trademarks

"Philips" and "Hue" are trademarks of Signify B.V. This project is not affiliated with, endorsed by, or officially connected to Signify or Philips.

## Acknowledgments

- Philips Hue for the excellent API and hardware
- Apple for SwiftUI, WatchKit, and AppKit frameworks
- The Swift community for open-source tools and inspiration
- [Claude Code](https://claude.com/claude-code) by Anthropic for collaborative development of the iOS app, multi-step loading system, SSE lifecycle improvements, and comprehensive documentation
