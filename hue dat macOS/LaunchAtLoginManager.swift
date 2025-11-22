//
//  LaunchAtLoginManager.swift
//  hue dat macOS
//
//  Manages launch at login functionality using ServiceManagement framework
//

import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let userDefaults = UserDefaults.standard
    private let launchAtLoginKey = "LaunchAtLogin"

    private init() {}

    /// Get the current launch at login preference from UserDefaults
    var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: launchAtLoginKey)
        }
        set {
            userDefaults.set(newValue, forKey: launchAtLoginKey)
            userDefaults.synchronize()
        }
    }

    /// Get the actual system status of launch at login
    var systemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Enable launch at login
    func enable() throws {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
        } catch {
            throw LaunchAtLoginError.registrationFailed(error)
        }
    }

    /// Disable launch at login
    func disable() throws {
        do {
            try SMAppService.mainApp.unregister()
            isEnabled = false
        } catch {
            throw LaunchAtLoginError.unregistrationFailed(error)
        }
    }

    /// Apply the saved preference (call on app launch)
    func applySavedPreference() {
        let shouldBeEnabled = isEnabled
        let currentStatus = systemStatus

        // Sync UserDefaults preference with actual system status
        switch currentStatus {
        case .enabled:
            if !shouldBeEnabled {
                // System has it enabled but user preference says disabled
                try? disable()
            }
        case .notRegistered:
            if shouldBeEnabled {
                // System doesn't have it but user preference says enabled
                try? enable()
            }
        case .requiresApproval:
            // User needs to approve in System Settings
            // Keep the preference but don't change anything
            break
        case .notFound:
            // Service not found, likely a development/debugging issue
            break
        @unknown default:
            break
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case registrationFailed(Error)
    case unregistrationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let error):
            return "Failed to enable launch at login: \(error.localizedDescription)"
        case .unregistrationFailed(let error):
            return "Failed to disable launch at login: \(error.localizedDescription)"
        }
    }
}
