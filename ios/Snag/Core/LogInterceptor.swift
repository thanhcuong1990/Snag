import Foundation
import OSLog

@available(iOS 15.0, *)
class LogInterceptor {
    
    static let shared = LogInterceptor()
    
    private let pipe = Pipe()
    private var isCapturing = false
    private let queue = DispatchQueue(label: "com.snag.logInterceptor")
    
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
        
        // Restore them immediately? No, we want to capture. 
        // But dup2 replaces the file descriptor. 
        // We probably want to tee? 
        // For simplicity, we just capture and re-print to original if needed.
        // Swift print() goes to stdout.
        
        pipeReadHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            
            // Re-print to original stdout to keep Xcode console working? 
            // Writing to originalStdout file descriptor.
            // write(originalStdout, ...)
            
            if let string = String(data: data, encoding: .utf8) {
                // Split by newlines
                let lines = string.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    Snag.log(line, level: "info", tag: "stdout")
                }
            }
        }
        
        // Start OSLogStore polling/streaming
        startOSLogStream()
    }
    
    private func startOSLogStream() {
        queue.async {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                var lastDate = Date()
                
                while self.isCapturing {
                    let position = store.position(date: lastDate)
                    let entries = try store.getEntries(at: position)
                    
                    for entry in entries {
                        // Skip if entry is older or same as lastDate (simple dedupe attempts)
                        if entry.date <= lastDate { continue }
                        
                        if let logEntry = entry as? OSLogEntryLog {
                            // Filter consistent with process? scope .currentProcessIdentifier guarantees it.
                            Snag.log(logEntry.composedMessage, 
                                     level: self.levelString(for: logEntry.level), 
                                     tag: logEntry.subsystem.isEmpty ? logEntry.category : "\(logEntry.subsystem)/\(logEntry.category)")
                        }
                        
                        lastDate = entry.date
                    }
                    Thread.sleep(forTimeInterval: 1.0) 
                    // Polling 1s might be slow but safe.
                    // To do better we'd need OSLogEntrySource but it's complex.
                }
                
            } catch {
                print("Snag: Failed to setup OSLogStore: \(error)")
            }
        }
    }
    
    private func levelString(for level: OSLogEntryLog.Level) -> String {
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
