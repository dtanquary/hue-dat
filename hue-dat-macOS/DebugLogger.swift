//
//  DebugLogger.swift
//  hue dat macOS
//
//  Debug logger that writes to a file for crash debugging
//

import Foundation

class DebugLogger {
    static let shared = DebugLogger()

    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.huedat.debuglogger", qos: .utility)

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Log file in user's home directory for easy access
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HueDat")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        fileURL = logDir.appendingPathComponent("huedat_debug.log")

        // Preserve previous session's log (critical for post-crash diagnosis)
        let previousLogURL = logDir.appendingPathComponent("huedat_debug_previous.log")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: previousLogURL)
            try? FileManager.default.moveItem(at: fileURL, to: previousLogURL)
        }

        // Create fresh log file for this session
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: fileURL)

        // Write startup header
        let startupMsg = """
        ========================================
        HueDat Debug Log Started
        Time: \(dateFormatter.string(from: Date()))
        ========================================

        """
        if let data = startupMsg.data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }

        log("Debug logger initialized")
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(fileName):\(line)] \(function): \(message)\n"

        // Print to console too
        print(logLine, terminator: "")

        // Write to file asynchronously
        queue.async { [weak self] in
            if let data = logLine.data(using: .utf8) {
                try? self?.fileHandle?.write(contentsOf: data)
                try? self?.fileHandle?.synchronize()  // Force flush to disk
            }
        }
    }

    func logSync(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(fileName):\(line)] \(function): \(message)\n"

        // Print to console too
        print(logLine, terminator: "")

        // Write to file synchronously (for critical moments before crash)
        queue.sync { [weak self] in
            if let data = logLine.data(using: .utf8) {
                try? self?.fileHandle?.write(contentsOf: data)
                try? self?.fileHandle?.synchronize()
            }
        }
    }

    var logFilePath: String {
        fileURL.path
    }

    var previousLogFilePath: String {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("huedat_debug_previous.log").path
    }

    // MARK: - Crash auto-relaunch

    // Pre-built at install time so crash handlers never touch Bundle/String/Date APIs.
    private static let startEpoch = time(nil)
    private static let relaunchArgv: [UnsafeMutablePointer<CChar>?] = {
        // sleep lets the dying instance exit first (avoids duplicate menu bar icons)
        let cmd = "sleep 2; /usr/bin/open \"\(Bundle.main.bundlePath)\""
        return ["/bin/sh", "-c", cmd].map { strdup($0) } + [nil]
    }()
    private static var relaunchScheduled = false

    /// Relaunch the app after a crash so the menu bar item comes back.
    /// Uses only time()/posix_spawn with pre-built C strings — best-effort
    /// async-signal-safety, same caveat as the logging in these handlers.
    /// ponytail: self-relaunch from crash handler; launchd KeepAlive agent if this proves flaky
    static func scheduleRelaunch() {
        // One-shot: the exception handler and the SIGABRT handler both fire for the same crash
        guard !relaunchScheduled else { return }
        // Crash-loop guard: never relaunch if we crashed within 30s of startup
        guard time(nil) - startEpoch > 30 else { return }
        relaunchScheduled = true
        var pid: pid_t = 0
        posix_spawn(&pid, relaunchArgv[0], nil, nil, relaunchArgv, nil)
    }

    /// Install signal handlers to capture crash info before the process dies
    func installCrashHandlers() {
        // Force-init relaunch statics now — lazy static init inside a signal handler could deadlock
        _ = DebugLogger.startEpoch
        _ = DebugLogger.relaunchArgv

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            signal(sig) { signalNumber in
                // UNSAFE in signal handler but best-effort for crash diagnosis
                let msg = "\n💥 CRASH: Received signal \(signalNumber) (\(DebugLogger.signalName(signalNumber)))\n"
                if let data = msg.data(using: .utf8),
                   let handle = DebugLogger.shared.fileHandle {
                    try? handle.write(contentsOf: data)
                    try? handle.synchronize()
                }
                DebugLogger.scheduleRelaunch()
                // Re-raise to get default crash behavior (generates crash report)
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }

    /// Also install NSException handler for Objective-C exceptions
    func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let msg = """
            \n💥 UNCAUGHT EXCEPTION: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack: \(exception.callStackSymbols.joined(separator: "\n"))\n
            """
            if let data = msg.data(using: .utf8),
               let handle = DebugLogger.shared.fileHandle {
                try? handle.write(contentsOf: data)
                try? handle.synchronize()
            }
            DebugLogger.scheduleRelaunch()
        }
    }

    static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGILL:  return "SIGILL"
        case SIGFPE:  return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default:      return "UNKNOWN(\(sig))"
        }
    }
}

// Convenience global function
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.log(message, file: file, function: function, line: line)
}

// Synchronous version for critical moments
func debugLogSync(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.logSync(message, file: file, function: function, line: line)
}
