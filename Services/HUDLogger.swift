//
//  HUDLogger.swift
//  ClaudeHUD
//
//  Central Debug & Diagnostic Logger
//  Streams colorized, timestamped debug logs to stdout and /tmp/claude-hud.log
//

import Foundation

public final class HUDLogger: @unchecked Sendable {
    public static let shared = HUDLogger()
    
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.claudehud.logger", qos: .utility)
    private let dateFormatter: DateFormatter
    
    private init() {
        self.logFileURL = URL(fileURLWithPath: "/tmp/claude-hud.log")
        
        // Ensure file exists or create clean
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        log("=================================================================")
        log("🚀 Claude HUD Debug Logger Initialized")
        log("📁 Log file: \(logFileURL.path)")
        log("⏰ Started: \(Date())")
        log("=================================================================")
    }
    
    public func log(_ message: String, category: String = "HUD", file: String = #file, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let time = self.dateFormatter.string(from: Date())
            let fileName = (file as NSString).lastPathComponent
            let logLine = "[\(time)] [\(category)] [\(fileName):\(line)] \(message)\n"
            
            // Print to standard out for terminal users
            print(logLine, terminator: "")
            fflush(stdout)
            
            // Write to /tmp/claude-hud.log
            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
                try? self.fileHandle?.synchronize()
            }
        }
    }
}

public func hudLog(_ message: String, category: String = "DEBUG", file: String = #file, line: Int = #line) {
    HUDLogger.shared.log(message, category: category, file: file, line: line)
}
