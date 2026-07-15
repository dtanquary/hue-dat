//
//  DebugLog_watchOS.swift
//  hue dat Watch App
//
//  Debug-only print wrapper. Defined per-target (not in HueDatShared) so the
//  macOS target's file-logging debugLog never loses overload resolution to it.
//

/// Compiles to a no-op in release builds. @autoclosure so string
/// interpolation is never evaluated in release.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
