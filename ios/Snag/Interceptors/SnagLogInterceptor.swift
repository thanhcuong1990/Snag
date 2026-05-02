import Foundation
import OSLog

@available(iOS 15.0, *)
actor SnagLogInterceptor {

    static let shared = SnagLogInterceptor()

    private let pipe = Pipe()
    private var isCapturing = false
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    private let stdoutBatchQueue = DispatchQueue(label: "com.snag.log.stdoutBatch")
    private var stdoutBuffer: String = ""
    private var stdoutBatchScheduled: Bool = false
    private let stdoutBatchInterval: DispatchTimeInterval = .milliseconds(100)
    private let stdoutBatchMaxBytes: Int = 32_768

    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true

        // Capture stdout/stderr via dup2
        let pipeReadHandle = pipe.fileHandleForReading
        let pipeFileDescriptor = pipe.fileHandleForWriting.fileDescriptor

        // Save original stdout/stderr to restore/echo
        let stdoutFd = dup(STDOUT_FILENO)
        let stderrFd = dup(STDERR_FILENO)
        originalStdout = stdoutFd
        originalStderr = stderrFd

        dup2(pipeFileDescriptor, STDOUT_FILENO)
        dup2(pipeFileDescriptor, STDERR_FILENO)

        let batchQueue = self.stdoutBatchQueue
        pipeReadHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }

            // Echo back to original stdout so it shows in Xcode console
            if stdoutFd != -1 {
                data.withUnsafeBytes { ptr in
                    _ = write(stdoutFd, ptr.baseAddress, data.count)
                }
            }

            guard let chunk = String(data: data, encoding: .utf8) else { return }
            // Coalesce reads on a serial queue and let the actor pull a batch on a timer.
            batchQueue.async {
                Task { [weak self] in
                    await self?.appendStdoutChunk(chunk)
                }
            }
        }

        // Start OSLogStore polling/streaming
        startOSLogStream()
    }

    private func appendStdoutChunk(_ chunk: String) {
        stdoutBuffer.append(chunk)
        if stdoutBuffer.count >= stdoutBatchMaxBytes {
            flushStdoutBuffer()
            return
        }
        if !stdoutBatchScheduled {
            stdoutBatchScheduled = true
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                await self?.flushStdoutBuffer()
            }
        }
    }

    private func flushStdoutBuffer() {
        stdoutBatchScheduled = false
        guard !stdoutBuffer.isEmpty else { return }
        let message = stdoutBuffer
        stdoutBuffer.removeAll(keepingCapacity: true)

        let maxLength = 10_000
        let trimmed = message.count > maxLength ? String(message.prefix(maxLength)) + "... (truncated in interceptor)" : message
        Snag.log(trimmed, level: "info", tag: "stdout")
    }
    
    func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false

        // Restore stdout/stderr
        if originalStdout != -1 {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            originalStdout = -1
        }
        if originalStderr != -1 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        flushStdoutBuffer()
    }
    
    private func startOSLogStream() {
        // Use a detached task to avoid blocking the actor's executor with OSLogStore setup
        Task.detached(priority: .background) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                var lastDate = Date()
                
                while !Task.isCancelled {
                    // Check capturing state from the actor
                    let active = await SnagLogInterceptor.shared.getIsCapturing()
                    if !active { break }
                    
                    do {
                        let position = store.position(date: lastDate)
                        let entries = try store.getEntries(at: position)
                        
                        for entry in entries {
                            if entry.date <= lastDate { continue }
                            
                            if let logEntry = entry as? OSLogEntryLog {
                                let message = logEntry.composedMessage
                                let level = SnagLogInterceptor.levelString(for: logEntry.level)
                                let tag = logEntry.subsystem.isEmpty ? logEntry.category : "\(logEntry.subsystem)/\(logEntry.category)"
                                
                                Snag.log(message, level: level, tag: tag)
                            }
                            
                            lastDate = entry.date
                        }
                    } catch {
                        Snag.internalDebugLog("Snag: Log stream error: \(error)")
                    }
                    
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms polling
                }
            } catch {
                Snag.internalDebugLog("Snag: Failed to setup OSLogStore: \(error)")
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
