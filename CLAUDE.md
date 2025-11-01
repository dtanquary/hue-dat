# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a native watchOS application for controlling Philips Hue lights directly from Apple Watch, without requiring an iPhone companion app. The app discovers Hue bridges on the local network and registers with them to enable light control.

## Build and Development Commands

### Building the Project
```bash
# Open in Xcode (spaces in path require escaping)
open "hue dat.xcodeproj"

# Build for watchOS Simulator
xcodebuild -project "hue dat.xcodeproj" -scheme "hue dat Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build

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
   - Uses `InsecureURLSessionDelegate` to bypass SSL certificate validation (required for local HTTPS bridges)
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
All models are defined in `Models/BridgeModels.swift`:
- **BridgeInfo**: Basic bridge network information (ID, IP, port)
- **BridgeConnectionInfo**: Complete connection state including credentials and connection date
- **BridgeRegistrationResponse**: API response from successful registration
- **BridgeRegistrationError**: Custom error types for registration failures

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
  - Displays grouped light status (on/off, brightness, color temp, XY color)
  - Uses Hue API v2 `/clip/v2/resource/grouped_light/{id}` endpoint

- **ZoneDetailView**: Individual zone control interface
  - Same functionality as RoomDetailView but for zones
  - Dedicated zone icon (square.3.layers.3d)

- **BridgesListView**: Bridge selection and registration UI
  - Presents discovered bridges
  - Manages per-bridge registration flow

Views use `@StateObject` for service ownership and `@ObservedObject`/`@Published` for reactive updates

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
The app uses `InsecureURLSessionDelegate` in `BridgeRegistrationService.swift:189` to accept self-signed certificates from local Hue bridges. This is necessary because bridges use HTTPS with self-signed certs. Do not remove this unless implementing proper certificate pinning.

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
│   ├── BridgeDiscoveryService.swift    # Network discovery
│   └── BridgeRegistrationService.swift # Registration/pairing
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
