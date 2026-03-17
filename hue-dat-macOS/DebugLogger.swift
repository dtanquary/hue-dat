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

    /// Install signal handlers to capture crash info before the process dies
    func installCrashHandlers() {
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
