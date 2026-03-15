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

        // Create or truncate log file at startup
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
}

// Convenience global function
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.log(message, file: file, function: function, line: line)
}

// Synchronous version for critical moments
func debugLogSync(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.logSync(message, file: file, function: function, line: line)
}
