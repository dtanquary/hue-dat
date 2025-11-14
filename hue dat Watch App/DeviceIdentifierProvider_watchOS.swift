//
//  DeviceIdentifierProvider_watchOS.swift
//  hue dat Watch App
//
//  Platform-specific device identifier implementation for watchOS
//

import Foundation
import WatchKit
import HueDatShared

/// watchOS implementation of DeviceIdentifierProvider
class WatchOSDeviceIdentifierProvider: DeviceIdentifierProvider {
    func getDeviceIdentifier() -> UUID? {
        return WKInterfaceDevice.current().identifierForVendor
    }
}
