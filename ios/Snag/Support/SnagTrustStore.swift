import Foundation
import CryptoKit
import Security
import Network

struct SnagTrustMetricsSnapshot {
    let trustedServerCount: Int
    let mismatchCount: Int
}

enum SnagTrustDecision: Equatable {
    case trusted
    case mismatch(expectedFingerprint: String, actualFingerprint: String)
    case invalid
}

final class SnagTrustStore {
    static let shared = SnagTrustStore()

    private let storageKey = "SnagTrustedServerFingerprints"
    private let mismatchCountKey = "SnagTrustedServerMismatchCount"
    private let queue = DispatchQueue(label: "com.snag.truststore.queue")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func verifyOrTrust(serverKey: String, secTrust: sec_trust_t) -> SnagTrustDecision {
        let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
        guard SecTrustGetCertificateCount(trust) > 0,
              let leaf = SecTrustGetCertificateAtIndex(trust, 0) else {
            return .invalid
        }

        let certData = SecCertificateCopyData(leaf) as Data
        let fingerprint = SHA256.hash(data: certData).map { String(format: "%02x", $0) }.joined()
        return verifyOrTrust(serverKey: serverKey, fingerprint: fingerprint)
    }

    func verifyOrTrust(serverKey: String, fingerprint: String) -> SnagTrustDecision {
        return queue.sync {
            var map = loadMap()
            if let existing = map[serverKey] {
                if existing != fingerprint {
                    let mismatchCount = defaults.integer(forKey: mismatchCountKey) + 1
                    defaults.set(mismatchCount, forKey: mismatchCountKey)
                    print("SnagTrustStore: TLS fingerprint mismatch for \(serverKey)")
                    return .mismatch(expectedFingerprint: existing, actualFingerprint: fingerprint)
                }
                return .trusted
            }

            map[serverKey] = fingerprint
            defaults.set(map, forKey: storageKey)
            print("SnagTrustStore: Trusted new server fingerprint for \(serverKey)")
            return .trusted
        }
    }

    func resetAll() {
        queue.sync {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: mismatchCountKey)
        }
    }

    func metricsSnapshot() -> SnagTrustMetricsSnapshot {
        return queue.sync {
            let map = loadMap()
            return SnagTrustMetricsSnapshot(
                trustedServerCount: map.count,
                mismatchCount: defaults.integer(forKey: mismatchCountKey)
            )
        }
    }

    private func loadMap() -> [String: String] {
        return defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}
