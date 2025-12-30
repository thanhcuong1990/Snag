import Cocoa

extension String {
    
    var base64Data: Data? {
        return Data(base64Encoded: self, options: .ignoreUnknownCharacters)
    }
    
    func extractDomain() -> String? {
        let s = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let host = URL(string: s)?.host, !host.isEmpty { return host }
        if !s.contains("://"), let host = URL(string: "https://" + s)?.host, !host.isEmpty { return host }
        return nil
    }

    func mainDomain() -> String {
        let h = self.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if h.isEmpty { return self }
        if h == "localhost" { return h }
        if h.contains(":") { return h }
        let parts = h.split(separator: ".").map { String($0) }
        if parts.count < 2 { return h }
        if parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return h }
        return parts.suffix(2).joined(separator: ".")
    }
}

extension URL {
    
    func toKeyValueArray() -> [KeyValue] {
        
        var array = [KeyValue]()
        
        if let queryItems = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems {
            
            for queryItem in queryItems {
                
                array.append(KeyValue(key: queryItem.name, value: queryItem.value))
                
            }
        }
        
        return array
    }
}

extension Dictionary where Key == String, Value == String {
    
    func toKeyValueArray() -> [KeyValue] {
        
        var array = [KeyValue]()
        
        for key in self.keys {
            array.append(KeyValue(key: key, value: self[key]))
        }
        
        return array
    }
}
