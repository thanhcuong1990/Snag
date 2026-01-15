import Foundation

public struct SnagProject: Sendable {
    public var name: String?
    public var appIcon: String?
    public var bundleId: String?
    
    enum CodingKeys: String, CodingKey {
        case name = "projectName"
        case appIcon = "appIcon"
        case bundleId = "bundleId"
    }
}

extension SnagProject: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.appIcon = try container.decodeIfPresent(String.self, forKey: .appIcon)
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(appIcon, forKey: .appIcon)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
    }
}

