import Foundation

class SnagPublisherStore {
    private let knownPINsKey = "SnagKnownPINs"
    private let failedAttemptsKey = "SnagFailedAuthAttempts"
    private let lockedOutDevicesKey = "SnagLockedOutDevices"
    
    private(set) var knownPINs: [String: String] = [:]
    private(set) var failedAuthAttempts: [String: Int] = [:]
    private(set) var lockedOutDevices: [String: Date] = [:]
    
    init() {
        loadAll()
    }
    
    func loadAll() {
        // Load known PINs
        if let savedPINs = UserDefaults.standard.dictionary(forKey: knownPINsKey) as? [String: String] {
            knownPINs = savedPINs
        }
        
        // Load failed attempts
        failedAuthAttempts = UserDefaults.standard.dictionary(forKey: failedAttemptsKey) as? [String: Int] ?? [:]
        
        // Load lockout state
        if let savedTimestamps = UserDefaults.standard.dictionary(forKey: lockedOutDevicesKey) as? [String: Double] {
            lockedOutDevices = savedTimestamps.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }
    
    func authorizeDevice(deviceId: String, pin: String) {
        knownPINs[deviceId] = pin
        failedAuthAttempts.removeValue(forKey: deviceId)
        saveState()
    }
    
    func recordFailedAttempt(deviceId: String, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        let attempts = (failedAuthAttempts[deviceId] ?? 0) + 1
        failedAuthAttempts[deviceId] = attempts
        
        if attempts >= maxFailedAttempts {
            lockedOutDevices[deviceId] = Date().addingTimeInterval(lockoutDuration)
        }
        saveLockoutState()
    }
    
    func clearLockout(deviceId: String) {
        lockedOutDevices.removeValue(forKey: deviceId)
        failedAuthAttempts.removeValue(forKey: deviceId)
        saveLockoutState()
    }
    
    func removeKnownPIN(deviceId: String) {
        knownPINs.removeValue(forKey: deviceId)
        saveState()
    }
    
    private func saveState() {
        UserDefaults.standard.set(knownPINs, forKey: knownPINsKey)
    }
    
    private func saveLockoutState() {
        UserDefaults.standard.set(failedAuthAttempts, forKey: failedAttemptsKey)
        let lockedOutTimestamps = lockedOutDevices.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(lockedOutTimestamps, forKey: lockedOutDevicesKey)
    }
}
