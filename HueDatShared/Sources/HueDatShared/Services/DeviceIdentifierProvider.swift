//
//  DeviceIdentifierProvider.swift
//  HueDatShared
//
//  Protocol for platform-specific device identifier generation
//

import Foundation

/// Protocol for providing platform-specific device identifiers
public protocol DeviceIdentifierProvider {
    /// Returns a unique identifier for the current device
    /// - Returns: A UUID string representing the device
    func getDeviceIdentifier() -> UUID?
}
