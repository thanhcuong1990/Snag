import Foundation
import OSLog

@available(iOS 15.0, *)
actor LogInterceptor {
    
    static let shared = LogInterceptor()
    
    private let pipe = Pipe()
    private var isCapturing = false
    
    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // Capture stdout/stderr via dup2
        let pipeReadHandle = pipe.fileHandleForReading
        let pipeFileDescriptor = pipe.fileHandleForWriting.fileDescriptor
        
        // Save original stdout/stderr (discarding result as we don't restore them yet)
        _ = dup(STDOUT_FILENO)
        _ = dup(STDERR_FILENO)
        
        dup2(pipeFileDescriptor, STDOUT_FILENO)
        dup2(pipeFileDescriptor, STDERR_FILENO)
        
        pipeReadHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            
            if let string = String(data: data, encoding: .utf8) {
                // Limit message length to prevent excessive packet size
                let maxLength = 10_000
                let message = string.count > maxLength ? String(string.prefix(maxLength)) + "... (truncated in interceptor)" : string
                
                Task { @MainActor in
                    Snag.log(message, level: "info", tag: "stdout")
                }
            }
        }
        
        // Start OSLogStore polling/streaming
        startOSLogStream()
    }
    
    private func startOSLogStream() {
        // Use a detached task to avoid blocking the actor's executor with OSLogStore setup
        Task.detached(priority: .background) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                var lastDate = Date()
                
                while !Task.isCancelled {
                    // Check capturing state from the actor
                    let active = await LogInterceptor.shared.getIsCapturing()
                    if !active { break }
                    
                    do {
                        let position = store.position(date: lastDate)
                        let entries = try store.getEntries(at: position)
                        
                        for entry in entries {
                            if entry.date <= lastDate { continue }
                            
                            if let logEntry = entry as? OSLogEntryLog {
                                let message = logEntry.composedMessage
                                let level = LogInterceptor.levelString(for: logEntry.level)
                                let tag = logEntry.subsystem.isEmpty ? logEntry.category : "\(logEntry.subsystem)/\(logEntry.category)"
                                
                                Task { @MainActor in
                                    Snag.log(message, level: level, tag: tag)
                                }
                            }
                            
                            lastDate = entry.date
                        }
                    } catch {
                        print("Snag: Log stream error: \(error)")
                    }
                    
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000) // 1 second
                }
            } catch {
                print("Snag: Failed to setup OSLogStore: \(error)")
            }
        }
    }
    
    // Helper to allow external/detached access to capturing state
    func getIsCapturing() -> Bool {
        return isCapturing
    }
    
    private static func levelString(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        case .undefined: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
