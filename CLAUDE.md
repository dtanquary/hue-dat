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

### Data Models
All models are defined in `Models/BridgeModels.swift`:
- **BridgeInfo**: Basic bridge network information (ID, IP, port)
- **BridgeConnectionInfo**: Complete connection state including credentials and connection date
- **BridgeRegistrationResponse**: API response from successful registration
- **BridgeRegistrationError**: Custom error types for registration failures

### View Layer
- **ContentView**: Main entry point, handles discovery flow and connected state display
- **BridgesListView**: Presents discovered bridges and manages per-bridge registration UI
- Views use `@StateObject` for service ownership and `@ObservedObject`/`@Published` for reactive updates

### State Management
All services use `@MainActor` to ensure UI updates happen on the main thread. Services are `ObservableObject` instances with `@Published` properties for reactive SwiftUI bindings.

## Important Implementation Details

### SSL Certificate Handling
The app uses `InsecureURLSessionDelegate` in `BridgeRegistrationService.swift:179` to accept self-signed certificates from local Hue bridges. This is necessary because bridges use HTTPS with self-signed certs. Do not remove this unless implementing proper certificate pinning.

### Discovery Strategy
The production implementation uses the Philips Hue Discovery API endpoint (`discovery.meethue.com`) rather than local mDNS. The mDNS implementation exists but is commented out. The discovery endpoint approach works reliably but requires internet connectivity.

### Link Button Flow
Bridge registration requires the physical link button on the bridge to be pressed. The `BridgeRegistrationService` handles the two-step process:
1. First attempt returns error type 101 ("link button not pressed")
2. User presses physical button on bridge
3. Retry succeeds and returns credentials

### Persistence
Connected bridge information is stored in UserDefaults with the key "ConnectedBridge". The app automatically loads the saved connection on launch via `BridgeManager.init()`.

## File Organization

```
hue dat Watch App/
├── hue_datApp.swift                    # App entry point
├── ContentView.swift                   # Main view
├── Models/
│   └── BridgeModels.swift              # All data models
├── Managers/
│   └── BridgeManager.swift             # Connection persistence
├── Services/
│   ├── BridgeDiscoveryService.swift    # Network discovery
│   └── BridgeRegistrationService.swift # Registration/pairing
└── Views/
    └── BridgesListView.swift           # Bridge selection UI
```

## API Integration

### Hue API Endpoints Used
- **Discovery**: `GET https://discovery.meethue.com` - Returns all bridges associated with user's network
- **Registration**: `POST https://{bridge-ip}/api` - Creates new API user with device type and client key

### Request Format (Registration)
```json
{
  "devicetype": "hue_dat_watch_app#test1",
  "generateclientkey": true
}
```

### Response Format (Registration Success)
```json
[{
  "success": {
    "username": "...",
    "clientkey": "..."
  }
}]
```
