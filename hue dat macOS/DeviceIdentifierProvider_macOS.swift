//
//  DeviceIdentifierProvider_macOS.swift
//  hue dat macOS
//
//  Platform-specific device identifier implementation for macOS
//

import Foundation
import HueDatShared

/// macOS implementation of DeviceIdentifierProvider
class MacOSDeviceIdentifierProvider: DeviceIdentifierProvider {
    func getDeviceIdentifier() -> UUID? {
        // Try to get a stable identifier from IOKit hardware UUID
        // If that fails, fall back to a user defaults cached UUID

        // First, try to get the hardware UUID (most stable)
        if let hardwareUUID = getMacHardwareUUID() {
            return hardwareUUID
        }

        // Fallback: Use a cached UUID stored in UserDefaults
        let key = "MacOSDeviceIdentifier"
        if let uuidString = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }

        // Generate new UUID and cache it
        let newUUID = UUID()
        UserDefaults.standard.set(newUUID.uuidString, forKey: key)
        return newUUID
    }

    /// Attempts to get the Mac's hardware UUID from IOKit
    private func getMacHardwareUUID() -> UUID? {
        // Use IOPlatformUUID which is the hardware UUID for the Mac
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        guard let uuidString = serialNumberAsCFString.takeRetainedValue() as? String else {
            return nil
        }

        return UUID(uuidString: uuidString)
    }
}
