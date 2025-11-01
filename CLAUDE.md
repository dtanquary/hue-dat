# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a native watchOS application for controlling Philips Hue lights directly from Apple Watch, without requiring an iPhone companion app. The app discovers Hue bridges on the local network and registers with them to enable light control.

## Build and Development Commands

### Building the Project
```bash
# Open in Xcode (spaces in path require escaping)
open "hue dat.xcodeproj"

# Build for watchOS Simulator (adjust simulator name as needed)
xcodebuild -project "hue dat.xcodeproj" -scheme "hue dat Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build

# Build for device
xcodebuild -project "hue dat.xcodeproj" -scheme "hue dat Watch App" -destination 'generic/platform=watchOS' build
```

### Testing
The project does not currently have unit tests configured.

## Architecture

### Service Layer Architecture
The app uses a clean service-oriented architecture with three main services:

1. **BridgeDiscoveryService** (`Services/BridgeDiscoveryService.swift`): Handles network discovery of Hue bridges
   - Primary method: Discovery endpoint API (`https://discovery.meethue.com`)
   - Commented-out mDNS discovery via Network framework (Bonjour `_hue._tcp`)
   - Implements 15-minute caching strategy for discovery API results
   - Returns `[BridgeInfo]` models

2. **BridgeRegistrationService** (`Services/BridgeRegistrationService.swift`): Manages the bridge registration/pairing flow
   - Implements the "press link button" workflow required by Hue API
   - Uses `InsecureURLSessionDelegate` (from `Services/InsecureURLSessionDelegate.swift`) to bypass SSL certificate validation
   - Returns `BridgeRegistrationResponse` containing username and client key

3. **BridgeManager** (`Managers/BridgeManager.swift`): Persists and manages the active bridge connection
   - Stores `BridgeConnectionInfo` in UserDefaults
   - Tracks the currently connected bridge across app sessions
   - Provides connection lifecycle methods (save, disconnect, load)
   - **Hue API v2 Integration**: Fetches rooms, zones, and grouped light status
   - Validates connection and fetches live data from `/clip/v2/resource/` endpoints
   - Publishes connection validation results via Combine publisher
   - Includes comprehensive data models for `HueRoom`, `HueZone`, and `HueGroupedLight`

### Data Models

**Bridge Connection Models** (`Models/BridgeModels.swift`):
- **BridgeInfo**: Basic bridge network information (ID, IP, port)
- **BridgeConnectionInfo**: Complete connection state including credentials and connection date
- **BridgeRegistrationResponse**: API response from successful registration
- **BridgeRegistrationError**: Custom error types for registration failures
- **HueBridgeError** & **HueBridgeErrorResponse**: Error response structures

**Hue API v2 Models** (nested in `BridgeManager`):
- **HueRoom**: Room data including metadata (name, archetype), children, services, and grouped lights
- **HueZone**: Zone data with same structure as HueRoom
- **HueGroupedLight**: Aggregated light status including on/off, brightness, color temperature, and XY color
- **ConnectionValidationResult**: Enum for connection validation state (success/failure)

### View Layer
The app uses a navigation-based architecture with the following views:

- **ContentView**: Root view wrapper that manages lifecycle events
  - Handles connection validation on app launch and when scene becomes active
  - Manages 5-second refresh timer for live room/zone status updates
  - Wraps `MainMenuView` and coordinates with `BridgeManager`

- **MainMenuView**: Primary navigation hub
  - Shows bridge discovery UI when not connected
  - Shows navigation menu with "Rooms & Zones" option when connected
  - Includes disconnect functionality

- **RoomsAndZonesListView**: Lists all rooms and zones
  - Organized into sections (Rooms, Zones)
  - Shows live status (on/off, brightness) for each room/zone
  - Refresh button in toolbar to manually update data
  - Uses room archetype-specific icons (sofa, bed, kitchen, etc.)

- **RoomDetailView**: Individual room control interface
  - Power toggle button for the grouped light
  - Brightness slider (visible when lights are on)
  - **Digital Crown support**: Rotate the crown to adjust brightness (0-100%)
  - **Debounced API calls**: 400ms debounce prevents excessive bridge requests
  - Focus management with `@FocusState` for crown input
  - Displays grouped light status (on/off, brightness, color temp, XY color)
  - Uses Hue API v2 `/clip/v2/resource/grouped_light/{id}` endpoint

- **ZoneDetailView**: Individual zone control interface
  - Same functionality as RoomDetailView but for zones
  - Dedicated zone icon (square.3.layers.3d)
  - Includes Digital Crown support and debouncing

- **BridgesListView**: Bridge selection and registration UI
  - Presents discovered bridges
  - Manages per-bridge registration flow

Views use `@StateObject` for service ownership and `@ObservedObject`/`@Published` for reactive updates.

**Utility Extensions** (`ContentView.swift`):
- **Array\<Double>.average()**: Extension method to calculate average of Double arrays, used for aggregating brightness values across multiple lights in a room/zone

### State Management
All services use `@MainActor` to ensure UI updates happen on the main thread. Services are `ObservableObject` instances with `@Published` properties for reactive SwiftUI bindings.

## Important Implementation Details

### Device Identification
The app uses `WKInterfaceDevice.current().identifierForVendor` to generate a unique identifier for each Apple Watch (`BridgeRegistrationService.swift:85`). This ensures:
- Each watch gets its own registration on the bridge
- The identifier persists across app reinstalls
- Multiple watches can register to the same bridge without conflicts
- Device registrations appear as `hue_dat_watch_app#A1B2C3D4` (first 8 chars of UUID)

### SSL Certificate Handling
The app uses `InsecureURLSessionDelegate` (`Services/InsecureURLSessionDelegate.swift`) to accept self-signed certificates from local Hue bridges. This delegate is used by all services that communicate with the bridge (BridgeRegistrationService, BridgeManager). This is necessary because bridges use HTTPS with self-signed certs. Do not remove this unless implementing proper certificate pinning.

### Discovery Strategy
The production implementation uses the Philips Hue Discovery API endpoint (`discovery.meethue.com`) rather than local mDNS. The mDNS implementation exists but is commented out. The discovery endpoint approach works reliably but requires internet connectivity.

### Link Button Flow
Bridge registration requires the physical link button on the bridge to be pressed. The `BridgeRegistrationService` handles the two-step process:
1. First attempt returns error type 101 ("link button not pressed")
2. User presses physical button on bridge
3. Retry succeeds and returns credentials

The service includes comprehensive error handling that:
- Logs payloads, raw responses, and parsed JSON for debugging
- Handles all bridge error types with specific error messages
- Distinguishes between link button errors (type 101) and other bridge errors
- Provides detailed console output for troubleshooting registration issues

### Persistence
Connected bridge information is stored in UserDefaults with the key "ConnectedBridge". The app automatically loads the saved connection on launch via `BridgeManager.init()`.

### Live Status Updates
The app implements a 5-second refresh timer (managed in `ContentView`) that periodically fetches room and zone data when the app is active and connected to a bridge. This provides near-real-time status updates for all lights. The timer is automatically paused when the app goes into the background.

### Digital Crown Support & Debouncing
Both `RoomDetailView` and `ZoneDetailView` implement Digital Crown support for brightness control with critical debouncing:

**Digital Crown Implementation:**
- Uses `.digitalCrownRotation($brightness, from: 0, through: 100, by: 1, sensitivity: .low)` modifier
- Requires `.focusable()` and `.focused($isBrightnessFocused)` for focus management
- Crown rotation and slider both update the same `brightness` state variable
- Sensitivity set to `.low` for smoother, more controlled adjustments

**Debouncing Strategy (CRITICAL):**
- Both slider and crown input trigger `debouncedSetBrightness()` instead of direct API calls
- Uses `@State private var brightnessTask: Task<Void, Never>?` to track pending updates
- Previous pending tasks are cancelled when new input arrives
- 400ms delay (via `Task.sleep(nanoseconds: 400_000_000)`) before API call executes
- This prevents excessive API requests during rapid crown rotation or slider adjustments
- Without debouncing, rapid input could generate 100+ API calls, overwhelming the bridge

**Why Debouncing is Essential:**
- Hue bridges have rate limits and can become unresponsive with excessive requests
- Digital Crown rotation is continuous and can be very rapid
- A single brightness adjustment could trigger dozens of API calls without debouncing
- The 400ms delay balances responsiveness (feels instant) with API efficiency

## File Organization

```
hue dat Watch App/
├── hue_datApp.swift                    # App entry point
├── ContentView.swift                   # Root view wrapper & lifecycle manager
├── Models/
│   └── BridgeModels.swift              # Bridge connection data models
├── Managers/
│   └── BridgeManager.swift             # Connection persistence & Hue API v2 integration
├── Services/
│   ├── BridgeDiscoveryService.swift       # Network discovery
│   ├── BridgeRegistrationService.swift    # Registration/pairing
│   └── InsecureURLSessionDelegate.swift   # SSL certificate bypass for local bridges
└── Views/
    ├── MainMenuView.swift              # Primary navigation hub
    ├── RoomsAndZonesListView.swift     # List of all rooms & zones
    ├── RoomDetailView.swift            # Individual room control
    ├── ZoneDetailView.swift            # Individual zone control
    └── BridgesListView.swift           # Bridge selection UI
```

## API Integration

### Hue API Endpoints Used

#### Discovery & Registration (API v1)
- **Discovery**: `GET https://discovery.meethue.com` - Returns all bridges associated with user's network
- **Registration**: `POST https://{bridge-ip}/api` - Creates new API user with device type and client key

#### Control & Status (API v2)
The app uses Hue API v2 for all control and status operations:
- **Connection Validation**: `GET https://{bridge-ip}/clip/v2/resource`
- **Rooms**: `GET https://{bridge-ip}/clip/v2/resource/room` and `GET https://{bridge-ip}/clip/v2/resource/room/{id}`
- **Zones**: `GET https://{bridge-ip}/clip/v2/resource/zone` and `GET https://{bridge-ip}/clip/v2/resource/zone/{id}`
- **Grouped Lights**: `GET https://{bridge-ip}/clip/v2/resource/grouped_light/{id}` (for status)
- **Light Control**: `PUT https://{bridge-ip}/clip/v2/resource/grouped_light/{id}` (for control)

All v2 API requests include the `hue-application-key` header with the username obtained during registration.

### Request Format (Registration)
```json
{
  "devicetype": "hue_dat_watch_app#A1B2C3D4",
  "generateclientkey": true
}
```
Note: The device identifier (e.g., "A1B2C3D4") is the first 8 characters of the watch's `identifierForVendor` UUID, making each watch's registration unique.

### Response Format (Registration Success)
```json
[{
  "success": {
    "username": "...",
    "clientkey": "..."
  }
}]
```

### Response Format (Registration Error)
```json
[{
  "error": {
    "type": 101,
    "address": "/api",
    "description": "link button not pressed"
  }
}]
```
The app handles error type 101 specially to trigger the link button alert flow. Other error types are displayed as general errors.

### API v2 Request Format (Light Control)
```json
{
  "on": {
    "on": true
  },
  "dimming": {
    "brightness": 75.0
  }
}
```

### API v2 Response Format (Grouped Light Status)
```json
{
  "errors": [],
  "data": [{
    "id": "...",
    "type": "grouped_light",
    "on": {
      "on": true
    },
    "dimming": {
      "brightness": 75.0
    },
    "color_temperature": {
      "mirek": 366
    },
    "color": {
      "xy": {
        "x": 0.4573,
        "y": 0.41
      }
    }
  }]
}
```
