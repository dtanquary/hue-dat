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
        // Stable per-install UUID cached in UserDefaults; only used once at
        // bridge registration, so install-scoped stability is enough.
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
}
