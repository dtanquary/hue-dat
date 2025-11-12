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
The app uses a clean service-oriented architecture with four main services:

1. **BridgeDiscoveryService** (`Services/BridgeDiscoveryService.swift`): Handles network discovery of Hue bridges
   - Primary method: Discovery endpoint API (`https://discovery.meethue.com`)
   - Commented-out mDNS discovery via Network framework (Bonjour `_hue._tcp`)
   - Implements 15-minute caching strategy for discovery API results
   - Returns `[BridgeInfo]` models

2. **BridgeRegistrationService** (`Services/BridgeRegistrationService.swift`): Manages the bridge registration/pairing flow
   - Implements the "press link button" workflow required by Hue API
   - Uses `InsecureURLSessionDelegate` (from `Services/InsecureURLSessionDelegate.swift`) to bypass SSL certificate validation
   - Returns `BridgeRegistrationResponse` containing username and client key

3. **HueAPIService** (`Services/HueAPIService.swift`): Actor-based API service for all Hue bridge communication
   - **Thread-safe actor implementation** with shared singleton instance
   - **HTTP/2 Multiplexing**: Single URLSession for both REST API and SSE streaming
   - **REST API Methods**: Generic request handler, fetchRooms, fetchZones, fetchGroupedLights
   - **Control Methods**: setPower, setBrightness, adjustBrightness for grouped lights
   - **Scene Methods**: fetchScenes, activateScene
   - **Rate Limiting**: 1-second minimum interval between grouped light updates
   - **Connection Validation**: validateConnection method for testing bridge connectivity
   - **Server-Sent Events (SSE)**: Real-time event streaming from bridge (`/eventstream/clip/v2`)
   - **Combine Publishers**: `streamStateSubject` for stream state, `eventPublisher` for parsed SSE events
   - **Stream Management**: startEventStream, stopEventStream, automatic reconnection handling
   - Uses `InsecureURLSessionDelegate` for SSL certificate bypass
   - Configured with infinite timeouts for SSE streaming, 10-second timeouts for REST calls

4. **BridgeManager** (`Managers/BridgeManager.swift`): Persists and manages the active bridge connection
   - Stores `BridgeConnectionInfo` in UserDefaults
   - Caches `rooms` and `zones` separately in UserDefaults for offline access and faster app startup
   - Tracks the currently connected bridge across app sessions
   - Provides connection lifecycle methods (save, disconnect, load)
   - **Hue API v2 Integration**: Uses `HueAPIService` for all bridge communication
   - Validates connection and fetches live data from `/clip/v2/resource/` endpoints
   - Publishes connection validation results via Combine publisher (`connectionValidationPublisher`)
   - Includes comprehensive data models for `HueRoom`, `HueZone`, `HueGroupedLight`, and `HueLight`
   - **Automatic Periodic Refresh**: 60-second timer-based background refresh of rooms, zones, grouped lights, and scenes
   - **Last Refresh Timestamp**: `@Published var lastRefreshTimestamp: Date?` tracks when data was last updated
   - **Manual Refresh**: User-triggered refresh via toolbar button in `RoomsAndZonesListView`
   - **Smart Updates**: Only updates changed items in arrays to prevent UI flicker
   - **Targeted Refresh**: `refreshSingleRoom()` and `refreshSingleZone()` for fast UI updates after control actions
   - **Equatable Models**: All data models conform to Equatable/Hashable for efficient SwiftUI diffing

### Data Models

**Bridge Connection Models** (`Models/BridgeModels.swift`):
- **BridgeInfo**: Basic bridge network information (ID, IP, port, optional serviceName)
- **BridgeConnectionInfo**: Complete connection state including credentials and connection date
- **BridgeRegistrationResponse**: API response from successful registration
- **BridgeRegistrationError**: Custom error types for registration failures
- **HueBridgeError** & **HueBridgeErrorResponse**: Error response structures

**Server-Sent Events Models** (`Models/SSEEventModels.swift`):
- **SSEEvent**: Top-level wrapper for SSE events from Hue API v2 with creationtime, data array, id, and type
- **SSEEventType**: Enum for event types (update, add, delete, error)
- **SSEResourceType**: Enum for resource types (light, grouped_light, room, zone, scene, device, motion, button, etc.)
- **SSEEventData**: Individual resource update with state fields for lights, rooms, zones, and scenes
- **Nested State Types**: OnState, DimmingState, ColorTemperatureState, ColorState (with XYColor), MetadataState, ChildReference, ServiceReference, SceneStatus, SceneRecall
- **Processing Helpers**: `shouldProcessUpdate` property filters relevant events, `debugDescription` for logging
- **Array Extensions**: `allEventData`, `relevantUpdates`, `eventCountByType` for batch processing

**Hue API v2 Models** (nested in `BridgeManager`):
- **HueRoom**: Room data including metadata (name, archetype), children, services, grouped lights, and individual lights. Conforms to `Equatable` and `Hashable`.
- **HueZone**: Zone data with same structure as HueRoom. Conforms to `Equatable` and `Hashable`.
- **HueGroupedLight**: Aggregated light status including on/off, brightness, color temperature, and XY color. Conforms to `Equatable` and `Hashable`.
- **HueLight**: Individual light data with on/off, brightness, color, and metadata. Conforms to `Equatable` and `Hashable`.
- **ConnectionValidationResult**: Enum for connection validation state (success/failure)

All Hue models implement custom equality operators that compare only relevant state (id, metadata, light status) to enable efficient SwiftUI view updates.

**Device Abstraction Layer:**
The Hue API v2 uses a three-layer hierarchy for connecting rooms/zones to lights:
1. **Room/Zone** → Contains `children` array with `rtype="device"` (device IDs)
2. **Device** → Query `/clip/v2/resource/device/{deviceId}` to get device details
3. **Light** → Device has `services` array; find service with `rtype="light"` to get actual light ID
4. **Light Data** → Query `/clip/v2/resource/light/{lightId}` with the light ID from device services

**Critical Implementation Details:**
- Room/Zone `children` contain **device IDs**, NOT light IDs
- You CANNOT directly query `/clip/v2/resource/light/{deviceId}` - it will fail
- The correct flow is: `deviceId` (from child) → `fetchDeviceDetails()` → find light service → `lightId` → `fetchLightDetails()`
- `fetchDeviceDetails()` queries the device endpoint and returns a `HueDevice` with services
- `fetchLightDetails()` expects the actual light ID (obtained from device.services)
- During enrichment, fetched lights are stored in the `room.lights` or `zone.lights` array
- Views access individual light data via `room.lights` or `zone.lights` directly (no separate cache lookup needed)
- `lightCache` is keyed by actual light IDs and used for bulk operations

### View Layer
The app uses a navigation-based architecture with the following views:

- **ContentView**: Root view wrapper that manages lifecycle events
  - Handles connection validation on app launch and when scene becomes active
  - Listens to `connectionValidationPublisher` for validation results
  - Navigates to rooms/zones view on successful validation (data loads there, not here)
  - Wraps `MainMenuView` and coordinates with `BridgeManager`
  - **Periodic Refresh Management**: Starts/stops automatic background refresh based on app lifecycle
  - Starts refresh timer when app appears and becomes active
  - Stops refresh timer when app enters background or inactive state (battery conservation)
  - Includes utility extension: `Array<Double>.average()` for aggregating brightness values

- **MainMenuView**: Primary navigation hub
  - Shows bridge discovery UI when not connected
  - Shows navigation menu with "Rooms & Zones" option when connected
  - Auto-navigation to "Rooms & Zones" view on successful connection validation
  - Glass effect button styling
  - Bridge count display with tap-to-show functionality
  - Disconnect alert confirmation

- **RoomsAndZonesListView**: Lists all rooms and zones
  - Organized into sections (Rooms, Zones)
  - Shows live status (on/off, brightness) for each room/zone with colored status dots (green=on, gray=off)
  - Refresh button in toolbar to manually update data (with rotation animation)
  - **Last Refresh Timestamp Display**: Shows "Updated X ago" using relative time formatting in More section
  - Loading overlay during initial data fetch
  - Empty state with refresh button when no rooms/zones available
  - Task-based data loading on appear (ONLY place where automatic data loading occurs)
  - Uses room archetype-specific icons (sofa, bed, kitchen, etc.) with default fallback
  - Navigation to SettingsView via gear icon button

- **RoomDetailView**: Individual room control interface
  - Centered ON/OFF text with tap gesture for power toggle
  - Brightness bar on right side (8pt wide) with vertical drag gesture
  - **ColorOrbsBackground**: Animated gradient orb background with opacity directly tied to brightness slider (0-100%)
  - **Digital Crown support**: Rotate the crown to adjust brightness (0-100%) with `.low` sensitivity
  - **Drag-based brightness control**: Vertical drag on brightness bar (inverted Y-axis: top = 100%, bottom = 0%)
  - **Brightness percentage popover**: Shows on initial load and during adjustments (1-second auto-hide)
  - **Throttled API calls**: 300ms throttling prevents excessive bridge requests during rapid adjustments
  - **Optimistic UI updates**: Immediate UI response for power toggle and brightness changes with rollback on API failure
  - **NO post-action refreshes**: Power toggle, brightness changes, and scene activation do NOT trigger API refreshes
  - **Control locking**: Mutual exclusion prevents simultaneous power and brightness operations
  - **Haptic feedback**: Two-event system (`.start` on begin, `.success`/`.failure` on completion) for user-initiated changes only
  - **Error handling**: Bridge unreachable alert on API failures
  - **Loading state management**: `hasCompletedInitialLoad` flag (0.1s delay) prevents haptic feedback during initial programmatic brightness load
  - **Haptic reset on new session**: `hasGivenFinalBrightnessHaptic` flag resets when starting new adjustment session
  - Focus management with `@FocusState` for crown input
  - Scene picker with carousel display and activation
  - Displays grouped light status (on/off, brightness, color temp, XY color)
  - Uses Hue API v2 `/clip/v2/resource/grouped_light/{id}` endpoint

- **ZoneDetailView**: Individual zone control interface
  - Identical functionality to RoomDetailView but for zones
  - Includes all features: ColorOrbsBackground, crown support, drag control, haptics, control locking, optimistic updates, throttling, scene picker
  - NO post-action API refreshes (same as RoomDetailView)

- **ScenePickerView**: Scene selection and activation interface
  - Full-screen sheet with scene list
  - SceneRowView with carousel background showing scene colors
  - Haptic click feedback on scene selection
  - Back button navigation

- **SettingsView**: Application settings and bridge management
  - Displays bridge connection details (IP, Bridge ID, connection date)
  - Disconnect bridge option with confirmation alert
  - Accessible from RoomsAndZonesListView toolbar

- **ColorOrbsBackground**: Background visual component (ColorOrbsBackground.swift)
  - Integrated into RoomDetailView and ZoneDetailView with direct brightness slider connection
  - Used in ScenePickerView to display scene colors in compact mode
  - Accepts array of Color objects to display as gradient orbs
  - Two size modes: `.fullscreen` (for room/zone backgrounds) and `.compact` (for scene preview rows)
  - Uses GeometryReader for responsive sizing
  - Dynamic positioning: circular/spiral arrangement based on light count
  - Radial gradients from color to transparent with `.screen` blend mode for additive color mixing
  - Responsive orb sizing based on available space and light count
  - Opacity directly controlled by brightness slider value (brightness / 100.0) in detail views

- **BridgesListView**: Bridge selection and registration UI
  - List of discovered bridges with per-bridge registration state
  - Success and error alerts for registration flow
  - Link button alert with retry mechanism
  - Automatic connection save on successful registration
  - Done button disabled during active registration
  - Manual bridge entry option via "Add Bridge Manually" button

- **ManualBridgeEntryView**: Manual bridge IP address entry interface
  - Text fields for IP address (required) and bridge name (optional)
  - IP address validation with regex pattern and octet range checking (0-255)
  - Generates pseudo bridge ID from IP address (`manual_` prefix + IP with underscores)
  - Creates `BridgeInfo` with port 443 for HTTPS connection
  - Glass effect button styling matching app design
  - Callback-based architecture to pass entered bridge info to parent view

Views use `@StateObject` for service ownership and `@ObservedObject`/`@Published` for reactive updates.

### State Management
- **MainActor Isolation**: BridgeManager and BridgeDiscoveryService use `@MainActor` to ensure UI updates happen on the main thread
- **Actor-Based API Service**: HueAPIService uses Swift's `actor` for thread-safe concurrent access
- **ObservableObject Pattern**: Services are `ObservableObject` instances with `@Published` properties for reactive SwiftUI bindings
- **Combine Integration**: Stream state and events published via `PassthroughSubject` for decoupled architecture
- **Task Detachment**: JSON decoding performed in detached tasks to avoid actor isolation warnings with MainActor-isolated models

## Important Implementation Details

### Device Identification
The app uses `WKInterfaceDevice.current().identifierForVendor` to generate a unique identifier for each Apple Watch (`BridgeRegistrationService.swift:85`). This ensures:
- Each watch gets its own registration on the bridge
- The identifier persists across app reinstalls
- Multiple watches can register to the same bridge without conflicts
- Device registrations appear as `hue_dat_watch_app#A1B2C3D4` (first 8 chars of UUID)

### SSL Certificate Handling
The app uses `InsecureURLSessionDelegate` (`Services/InsecureURLSessionDelegate.swift`) to accept self-signed certificates from local Hue bridges. This delegate is used by all services that communicate with the bridge (BridgeRegistrationService, HueAPIService). This is necessary because bridges use HTTPS with self-signed certs. Do not remove this unless implementing proper certificate pinning.

### Error Handling
The app implements comprehensive error handling across multiple layers:

**HueAPIError (in HueAPIService):**
- `invalidURL`: Malformed URL construction
- `invalidResponse`: Non-HTTP response received
- `httpError(statusCode)`: HTTP errors with status code
- `decodingError(Error)`: JSON decoding failures with wrapped error
- All errors conform to `LocalizedError` for user-friendly descriptions

**StreamState (for SSE):**
- `idle`: No active connection
- `connecting`: Connection attempt in progress
- `connected`: Stream actively receiving events
- `disconnected(Error?)`: Stream ended (with optional error)
- `error(String)`: Stream error with description
- Conforms to `Equatable` for state comparison

**Bridge Registration Errors:**
- Link button error (type 101) triggers special retry flow
- Detailed console logging of payloads, raw responses, and parsed JSON
- Specific error messages for each bridge error type

**View-Level Error Handling:**
- Optimistic UI updates with automatic rollback on API failure
- Error alerts shown when bridge is unreachable
- Loading states prevent user actions during network operations

### Discovery Strategy
The production implementation uses the Philips Hue Discovery API endpoint (`discovery.meethue.com`) rather than local mDNS. The mDNS implementation exists but is commented out. The discovery endpoint approach works reliably but requires internet connectivity. The app also supports manual bridge IP entry via `ManualBridgeEntryView` for cases where automatic discovery fails.

### Rate Limiting (HueAPIService)
The `HueAPIService` implements server-side rate limiting to prevent overwhelming the Hue bridge:
- **Grouped Light Rate Limit**: 1-second minimum interval between control commands for the same grouped light
- **Per-Light Tracking**: Dictionary tracks last update timestamp for each grouped light ID
- **Automatic Throttling**: Control methods check rate limit and automatically sleep if needed
- **Wait Time Logging**: Console logs when rate limiting is applied and how long the wait is
- **Individual Light Rate Limit**: Configurable at 0.1 seconds (10 per second) for future individual light control
- **Why Necessary**: Prevents excessive API requests that could make the bridge unresponsive
- **Complementary to View Debouncing**: Works alongside the 500ms debouncing in RoomDetailView/ZoneDetailView

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
The app uses UserDefaults for all persistence:
- **Bridge Connection**: Stored with key "ConnectedBridge", loaded automatically on launch via `BridgeManager.init()`
- **Rooms Cache**: Stored separately with key "cachedRooms" for offline access and faster app startup
- **Zones Cache**: Stored separately with key "cachedZones" for offline access and faster app startup
- Cached data is updated whenever fresh data is fetched from the bridge

### Data Refresh Architecture
The app uses an **automatic periodic refresh** strategy with manual override options:

**Automatic Periodic Refresh:**
- **60-second timer**: Automatically refreshes all data (rooms, zones, grouped lights, scenes) every 60 seconds
- **Lifecycle aware**: Timer starts when app becomes active, stops when entering background/inactive (battery conservation)
- **Managed by ContentView**: `startPeriodicRefresh()` and `stopPeriodicRefresh()` called based on scene phase
- **Initial refresh**: Immediate refresh triggered when timer starts
- **Timestamp tracking**: `lastRefreshTimestamp` property updated after each successful refresh
- **User visibility**: Last refresh time displayed in RoomsAndZonesListView as "Updated X ago"

**Manual Refresh Options:**
- **Initial load**: Data loads when first navigating to `RoomsAndZonesListView` (via `.task` modifier)
- **User-triggered refresh**: Toolbar button in `RoomsAndZonesListView` for immediate manual refresh
- **Respects debouncing**: 30-second minimum interval between refreshes prevents spam

**Refresh Behavior:**
- `refreshAllData()`: Refreshes rooms, zones, AND scenes in parallel using async let
- NO automatic refreshes after control actions (power toggle, brightness, scene activation)
- Data persists in cache between app launches
- Grouped light status enriched automatically during room/zone fetch

**Smart Update Logic:**
- `smartUpdateRooms()` and `smartUpdateZones()`: Only update array items that have actually changed
- Custom equality methods (`areRoomsEqual()`, `areZonesEqual()`, `areGroupedLightsEqual()`) compare state
- Preserves existing data during partial refreshes to prevent UI flicker
- Minimizes SwiftUI re-renders by only updating changed items

**Targeted Refresh (Available but not auto-triggered):**
- `refreshSingleRoom(roomId:)`: Fast refresh of just one room (3-4 API calls)
- `refreshSingleZone(zoneId:)`: Fast refresh of just one zone (3-4 API calls)
- Methods exist but are NOT called after control actions
- Can be manually invoked if needed in future
- Uses same smart update logic to only modify the specific room/zone in the array

### Digital Crown Support & Debouncing
Both `RoomDetailView` and `ZoneDetailView` implement Digital Crown support for brightness control with debouncing and haptic feedback:

**Digital Crown Implementation:**
- Uses `.digitalCrownRotation($brightness, from: 0, through: 100, by: 1, sensitivity: .low)` modifier
- Requires `.focusable()` and `.focused($isBrightnessFocused)` for focus management
- Crown rotation and drag bar both update the same `brightness` state variable
- Sensitivity set to `.low` for controlled, precise adjustments

**Drag Gesture Brightness Control:**
- Vertical drag gesture on brightness bar (8pt wide on right side)
- Inverted Y-axis: dragging up increases brightness, dragging down decreases
- Same debouncing system as crown rotation
- Visual feedback via animated brightness percentage popover
- Popover auto-hides after 1 second of inactivity

**Debouncing Strategy (CRITICAL):**
- Crown/drag input updates local brightness state immediately for instant visual feedback
- Uses Timer-based debouncing with 500ms delay
- Timer is cancelled and reset on every brightness change (debouncing behavior)
- API call only fires after user **stops adjusting** for 500ms
- More network-friendly than throttling: single API call per adjustment session instead of periodic calls
- Previous debounce timers are cancelled when new input arrives
- This prevents excessive API requests during rapid crown rotation or drag adjustments
- Without debouncing, rapid input could generate 100+ API calls, overwhelming the bridge

**Optimistic UI Updates:**
- Immediate UI response for both power toggle and brightness changes
- `optimisticIsOn` and `optimisticBrightness` track intended state
- `previousIsOn` and `previousBrightness` store last known good state
- On API failure: UI rolls back to previous state automatically
- On success: optimistic state becomes the new actual state
- Provides instant visual feedback while network request is in flight
- Error alert shown if bridge is unreachable

**Haptic Feedback System:**
- **Two-event pattern**: Initial haptic when adjustment starts, final haptic when network update completes
- Initial: `.start` haptic fires once when user begins adjusting (tracked by `hasGivenInitialBrightnessHaptic`)
- Final: `.success` haptic fires once when first network call completes (tracked by `hasGivenFinalBrightnessHaptic`)
- Error: `.failure` haptic if API request fails
- Both flags reset 1.5 seconds after user stops adjusting (via `brightnessHapticResetTimer`)
- **Session-based reset**: When starting a new adjustment (detected by `!hasGivenInitialBrightnessHaptic`), the `hasGivenFinalBrightnessHaptic` flag resets immediately, ensuring quick consecutive adjustments get completion haptics
- Same haptic pattern used for power toggle: `.start` on tap, `.success`/`.failure` after network completion
- **Loading state management**: `hasCompletedInitialLoad` flag set after 0.1s delay prevents haptic feedback during initial programmatic brightness load
- **Brightness popup behavior**: Shows on initial load (without haptic) and during user adjustments (with haptic)

**Control Locking (Mutual Exclusion):**
- `isTogglingPower` flag prevents brightness adjustment during power toggle operation
- `isSettingBrightness` flag prevents power toggle during brightness adjustment
- Guards at the start of `togglePower()` and brightness `onChange` enforce mutual exclusion
- Ensures only one network operation at a time, preventing race conditions and improving UX

**Why This Approach:**
- Hue bridges have rate limits and can become unresponsive with excessive requests
- Digital Crown rotation and drag gestures are continuous and can be very rapid
- The 500ms debounce delay allows user to settle on desired brightness before API call
- Debouncing is more network-friendly than throttling: one API call per adjustment vs multiple periodic calls
- Optimistic updates provide instant visual feedback, improving perceived performance
- Haptic feedback provides tactile confirmation without overwhelming the user
- Control locking prevents conflicting operations and ensures clean state transitions
- Error rollback ensures UI accurately reflects actual bridge state even when network fails

## File Organization

```
hue dat Watch App/
├── hue_datApp.swift                       # App entry point
├── ContentView.swift                      # Root view wrapper & lifecycle manager
├── Models/
│   ├── BridgeModels.swift                 # Bridge connection data models
│   └── SSEEventModels.swift               # Server-Sent Events data models for real-time updates
├── Managers/
│   └── BridgeManager.swift                # Connection persistence & Hue API v2 integration
├── Services/
│   ├── BridgeDiscoveryService.swift       # Network discovery
│   ├── BridgeRegistrationService.swift    # Registration/pairing
│   ├── HueAPIService.swift                # Actor-based API service with SSE streaming
│   └── InsecureURLSessionDelegate.swift   # SSL certificate bypass for local bridges
└── Views/
    ├── MainMenuView.swift                 # Primary navigation hub
    ├── RoomsAndZonesListView.swift        # List of all rooms & zones with status dots
    ├── RoomDetailView.swift               # Individual room control with haptics & orb
    ├── ZoneDetailView.swift               # Individual zone control with haptics & orb
    ├── ColorOrbsBackground.swift          # Animated gradient orb background component
    ├── ScenePickerView.swift              # Scene selection with orb preview backgrounds
    ├── SettingsView.swift                 # Settings and bridge management
    ├── BridgesListView.swift              # Bridge selection UI
    └── ManualBridgeEntryView.swift        # Manual bridge IP entry form
```

## API Integration

### Hue API Endpoints Used

#### Discovery & Registration (API v1)
- **Discovery**: `GET https://discovery.meethue.com` - Returns all bridges associated with user's network
- **Registration**: `POST https://{bridge-ip}/api` - Creates new API user with device type and client key

#### Control & Status (API v2)
The app uses Hue API v2 for all control and status operations via `HueAPIService`:
- **Connection Validation**: `GET https://{bridge-ip}/clip/v2/resource`
- **Rooms**: `GET https://{bridge-ip}/clip/v2/resource/room` and `GET https://{bridge-ip}/clip/v2/resource/room/{id}`
- **Zones**: `GET https://{bridge-ip}/clip/v2/resource/zone` and `GET https://{bridge-ip}/clip/v2/resource/zone/{id}`
- **Grouped Lights**: `GET https://{bridge-ip}/clip/v2/resource/grouped_light` and `GET https://{bridge-ip}/clip/v2/resource/grouped_light/{id}` (for status)
- **Light Control**: `PUT https://{bridge-ip}/clip/v2/resource/grouped_light/{id}` (for power and brightness control)
- **Scenes**: `GET https://{bridge-ip}/clip/v2/resource/scene` (list all scenes) and `PUT https://{bridge-ip}/clip/v2/resource/scene/{id}` (activate scene)

All v2 API requests include the `hue-application-key` header with the username obtained during registration.

#### Real-Time Updates (SSE)
The app supports Server-Sent Events for real-time light status updates:
- **Event Stream**: `GET https://{bridge-ip}/eventstream/clip/v2` (with `Accept: text/event-stream` header)
- **HTTP/2 Multiplexing**: SSE stream and REST API share same URLSession for efficient connection reuse
- **Event Processing**: Parses `data:` lines as JSON arrays of SSE events
- **Resource Types**: Receives updates for lights, grouped_lights, rooms, zones, scenes, devices, motion sensors, buttons, etc.
- **Stream State Management**: Automatic connection handling, reconnection on errors, graceful cancellation
- **Rate Limiting**: 1-second minimum interval between grouped light control commands to prevent bridge overload
- **Combine Integration**: Publishes parsed events via `eventPublisher`, stream state via `streamStateSubject`

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
