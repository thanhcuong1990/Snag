import Foundation

class SnagPublisherStore {
    private let authorizedDevicesKey = "SnagAuthorizedDeviceIds"
    private let knownPINsKey = "SnagKnownPINs"
    private let failedAttemptsKey = "SnagFailedAuthAttempts"
    private let lockedOutDevicesKey = "SnagLockedOutDevices"
    
    private(set) var manuallyAuthorizedDeviceIds: Set<String> = []
    private(set) var knownPINs: [String: String] = [:]
    private(set) var failedAuthAttempts: [String: Int] = [:]
    private(set) var lockedOutDevices: [String: Date] = [:]
    
    init() {
        loadAll()
    }
    
    func loadAll() {
        // Load authorized devices and normalize
        let savedAuthorized = UserDefaults.standard.stringArray(forKey: authorizedDevicesKey) ?? []
        manuallyAuthorizedDeviceIds = Set(savedAuthorized.map { $0.lowercased() })
        
        // Load known PINs and normalize keys
        if let savedPINs = UserDefaults.standard.dictionary(forKey: knownPINsKey) as? [String: String] {
            knownPINs = [:]
            for (key, value) in savedPINs {
                knownPINs[key.lowercased()] = value
            }
        }
        
        // Load failed attempts and normalize keys
        if let savedAttempts = UserDefaults.standard.dictionary(forKey: failedAttemptsKey) as? [String: Int] {
            failedAuthAttempts = [:]
            for (key, value) in savedAttempts {
                failedAuthAttempts[key.lowercased()] = value
            }
        }
        
        // Load lockout state and normalize keys
        if let savedTimestamps = UserDefaults.standard.dictionary(forKey: lockedOutDevicesKey) as? [String: Double] {
            lockedOutDevices = [:]
            for (key, value) in savedTimestamps {
                lockedOutDevices[key.lowercased()] = Date(timeIntervalSince1970: value)
            }
        }
    }
    
    func authorizeDevice(deviceId: String, pin: String) {
        let id = deviceId.lowercased()
        manuallyAuthorizedDeviceIds.insert(id)
        knownPINs[id] = pin
        failedAuthAttempts.removeValue(forKey: id)
        saveAuthorizedDevices()
    }
    
    func recordFailedAttempt(deviceId: String, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        let id = deviceId.lowercased()
        let attempts = (failedAuthAttempts[id] ?? 0) + 1
        failedAuthAttempts[id] = attempts
        
        if attempts >= maxFailedAttempts {
            lockedOutDevices[id] = Date().addingTimeInterval(lockoutDuration)
        }
        saveLockoutState()
    }
    
    func clearLockout(deviceId: String) {
        let id = deviceId.lowercased()
        lockedOutDevices.removeValue(forKey: id)
        failedAuthAttempts.removeValue(forKey: id)
        saveLockoutState()
    }
    
    func removeKnownPIN(deviceId: String) {
        let id = deviceId.lowercased()
        knownPINs.removeValue(forKey: id)
        saveAuthorizedDevices()
    }
    
    private func saveAuthorizedDevices() {
        UserDefaults.standard.set(Array(manuallyAuthorizedDeviceIds), forKey: authorizedDevicesKey)
        UserDefaults.standard.set(knownPINs, forKey: knownPINsKey)
    }
    
    private func saveLockoutState() {
        UserDefaults.standard.set(failedAuthAttempts, forKey: failedAttemptsKey)
        let lockedOutTimestamps = lockedOutDevices.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(lockedOutTimestamps, forKey: lockedOutDevicesKey)
    }
}
