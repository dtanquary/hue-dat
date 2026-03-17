//
//  AppLogger.swift
//  HueDatShared
//
//  Centralized logging for HueDat shared module using os.Logger
//

import os
import Foundation

/// Centralized logging for HueDat shared module
public enum AppLogger {
    public static let bridge = Logger(subsystem: "com.huedat", category: "bridge")
    public static let api = Logger(subsystem: "com.huedat", category: "api")
    public static let sse = Logger(subsystem: "com.huedat", category: "sse")
    public static let discovery = Logger(subsystem: "com.huedat", category: "discovery")
    public static let registration = Logger(subsystem: "com.huedat", category: "registration")
    public static let search = Logger(subsystem: "com.huedat", category: "search")
    public static let pinning = Logger(subsystem: "com.huedat", category: "pinning")
}

/// Debug-only print wrapper. Compiles to no-op in release builds.
/// Uses @autoclosure so string interpolation is never evaluated in release.
@inline(__always)
public func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
