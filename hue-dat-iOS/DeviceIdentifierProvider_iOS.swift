//
//  DeviceIdentifierProvider_iOS.swift
//  hue dat iOS
//
//  Platform-specific device identifier implementation for iOS
//

import UIKit
import HueDatShared

/// iOS implementation of DeviceIdentifierProvider
class IOSDeviceIdentifierProvider: DeviceIdentifierProvider {
    func getDeviceIdentifier() -> UUID? {
        return UIDevice.current.identifierForVendor
    }
}
