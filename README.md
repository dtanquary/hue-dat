# HueDat

Modern Philips Hue controller for watchOS, macOS, and iOS with native platform integration and real-time Server-Sent Events streaming.

## Overview

HueDat is a multi-platform Swift application providing seamless control of Philips Hue lights through native watchOS, macOS, and iOS applications. Built with SwiftUI and modern Swift concurrency, it features real-time updates via SSE, optimistic UI updates, and platform-specific optimizations including Digital Crown integration, macOS glass effects, and iOS touch-optimized controls with multi-step loading indicators.

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
- **Glass Effect Panel** - 320×480pt floating panel with `.ultraThinMaterial`
- **NSGlassEffectView** - Native glass effects for About dialog with private variant API support (0-19)
- **Click-Outside Dismissal** - Natural UX with global event monitoring
- **Scene Grid Cards** - Visual scene selection with instant feedback
- **SSE Status Indicator** - Color-coded connection status (green/blue/red/gray)
- **Bulk Light Control** - Manage all lights in rooms/zones simultaneously
- **Launch at Login** - Optional startup configuration

### iOS
- **Multi-Step Loading** - Visual progress indicators with step-by-step feedback ("Step X of Y")
- **Animated Bridge Discovery** - Rotating search icon during network discovery
- **Touch-Optimized Controls** - Native slider controls for brightness adjustment
- **Video Background** - Looping ambient video on main menu with scene phase management
- **Pull-to-Refresh** - Integrated gesture-based data refresh
- **Scene Grid** - Visual scene cards with tap activation
- **SSE Status Indicator** - Real-time connection monitoring
- **Validation Gating** - Smart loading that prevents premature data fetches
- **Instant Main Menu** - Zero-delay display when no bridge configured
- **App Resume Handling** - Automatic SSE reconnection with network stabilization delay
- **Smooth Animations** - Fade transitions between loading and loaded states

### Shared Features
- **Real-time SSE Streaming** - Instant updates from physical switches and other apps
- **HTTP/2 Multiplexing** - Single URLSession for efficient REST + SSE communication
- **Smart Updates** - Only modifies changed items to prevent UI flicker
- **60-second Auto-refresh** - Background data updates with lifecycle awareness
- **Rate Limiting** - 1-second minimum between grouped light updates
- **Bridge Discovery** - Automatic discovery via `https://discovery.meethue.com`
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
git clone <repository-url>
cd "hue dat"
```

### Open in Xcode

```bash
open "hue dat.xcodeproj"
```

### Build watchOS (Simulator)

```bash
xcodebuild -project "hue dat.xcodeproj" \
  -scheme "hue dat Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  build
```

### Build macOS

```bash
xcodebuild -project "hue dat.xcodeproj" \
  -scheme "hue dat macOS" \
  -destination 'platform=macOS' \
  build
```

### Build iOS (Simulator)

```bash
xcodebuild -project "hue dat.xcodeproj" \
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
- NSPopover-based floating panel (320×480pt)
- EventMonitor for click-outside detection
- IOKit hardware UUID for device identification
- NSGlassEffectView wrapper with private variant API
- LaunchAtLoginManager for startup configuration

#### iOS App
- SwiftUI App lifecycle with ContentView root manager
- Touch-optimized slider controls for brightness
- LoadingStepIndicator for multi-step progress tracking
- LoopingVideoPlayer with AVPlayerLooper for background video
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
hue dat/
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
│           └── BridgeManager.swift        # State & persistence
│
├── hue dat Watch App/                     # watchOS Target
│   ├── Views/
│   │   ├── ContentView.swift              # Lifecycle manager
│   │   ├── RoomDetailView.swift           # Digital Crown + haptics
│   │   ├── ColorOrbsBackground.swift      # Dynamic brightness orbs
│   │   └── [6 other views]
│   └── DeviceIdentifierProvider_watchOS.swift
│
├── hue dat macOS/                         # macOS Target
│   ├── HueDatMacApp.swift                # Menu bar + NSApplicationDelegate
│   ├── EventMonitor.swift                # Click-outside detection
│   ├── LaunchAtLoginManager.swift        # Startup configuration
│   ├── Views/
│   │   ├── MenuBarPanelView.swift
│   │   ├── GlassEffectView.swift         # NSGlassEffectView wrapper
│   │   ├── SSEStatusIndicator.swift      # Connection status
│   │   └── [6 other views]
│   └── DeviceIdentifierProvider_macOS.swift
│
└── hue dat iOS/                           # iOS Target
    ├── HueDatiOSApp.swift                # SwiftUI App entry
    ├── ContentView.swift                  # Lifecycle + SSE manager
    ├── DeviceIdentifierProvider_iOS.swift
    ├── Assets.xcassets/                   # App icons
    └── Views/
        ├── MainMenuView_iOS.swift         # Bridge discovery + video
        ├── RoomsAndZonesListView_iOS.swift # Primary data view
        ├── RoomDetailView_iOS.swift       # Touch controls
        ├── ZoneDetailView_iOS.swift       # Touch controls
        ├── LoadingStepIndicator.swift     # Multi-step progress
        ├── LoopingVideoPlayer.swift       # Background video
        └── [7 other views]
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

### Multi-Step Loading System (iOS)

**Problem**: Users perceive frozen app during data loading without feedback
**Solution**: LoadingStepIndicator with TaskGroup-based progress tracking

- Visual step dots show current progress (1-4 filled circles)
- Descriptive messages per step ("Preparing...", "Loading rooms...", "Loading zones...", "Loading scenes...")
- Parallel data fetching with TaskGroup monitors individual completion
- Smooth spring animations on step transitions
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

**Key Guidelines:**
- Follow existing code style (SwiftUI, actor-based concurrency)
- Test on all three platform targets (watchOS, macOS, iOS)
- Maintain platform abstraction via HueDatShared package
- Update CLAUDE.md if adding new architectural patterns
- Ensure iOS-specific features use touch-optimized controls

## License

This project is licensed under the MIT License - see below for details:

```
MIT License

Copyright (c) 2025 HueDat Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Acknowledgments

- Philips Hue for the excellent API and hardware
- Apple for SwiftUI, WatchKit, and AppKit frameworks
- The Swift community for open-source tools and inspiration
- [Claude Code](https://claude.com/claude-code) by Anthropic for collaborative development of the iOS app, multi-step loading system, SSE lifecycle improvements, and comprehensive documentation
