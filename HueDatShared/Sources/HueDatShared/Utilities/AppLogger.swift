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

// NOTE: No global debugLog here on purpose. A shared debugLog overload used to
// live in this file and Swift's overload resolution preferred it over the macOS
// target's file-logging debugLog (DebugLogger.swift) in every file importing
// HueDatShared — silently turning the macOS Release file log into a no-op.
// iOS/watchOS each define their own debugLog shim locally.
