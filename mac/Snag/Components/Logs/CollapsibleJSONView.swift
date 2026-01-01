import SwiftUI

/// A view that renders JSON as a collapsible tree structure
struct CollapsibleJSONView: View {
    let json: Any
    let level: Int
    
    init(json: Any, level: Int = 0) {
        self.json = json
        self.level = level
    }
    
    var body: some View {
        JSONNodeView(key: nil, value: json, level: level)
    }
}

/// Renders a single JSON node (key-value pair or array element)
struct JSONNodeView: View {
    let key: String?
    let value: Any
    let level: Int
    
    @State private var isExpanded: Bool = false
    
    private var indentation: CGFloat {
        CGFloat(level) * 12
    }
    
    private var isExpandable: Bool {
        value is [String: Any] || value is [Any]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let dict = value as? [String: Any] {
                objectView(dict: dict)
            } else if let array = value as? [Any] {
                arrayView(array: array)
            } else {
                primitiveView
            }
        }
    }
    
    // MARK: - Object View
    
    @ViewBuilder
    private func objectView(dict: [String: Any]) -> some View {
        // Header row
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 2) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                
                if let key = key {
                    Text("\(key):")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.purple)
                }
                
                Text(isExpanded ? "{" : "{\(dict.count)}")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.leading, indentation)
        }
        .buttonStyle(.plain)
        
        // Children
        if isExpanded {
            ForEach(dict.keys.sorted(), id: \.self) { childKey in
                if let childValue = dict[childKey] {
                    JSONNodeView(key: childKey, value: childValue, level: level + 1)
                }
            }
            
            Text("}")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, indentation)
        }
    }
    
    // MARK: - Array View
    
    @ViewBuilder
    private func arrayView(array: [Any]) -> some View {
        // Header row
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 2) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                
                if let key = key {
                    Text("\(key):")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.purple)
                }
                
                Text(isExpanded ? "[" : "[\(array.count)]")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.leading, indentation)
        }
        .buttonStyle(.plain)
        
        // Children
        if isExpanded {
            ForEach(Array(array.enumerated()), id: \.offset) { index, element in
                JSONNodeView(key: "\(index)", value: element, level: level + 1)
            }
            
            Text("]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, indentation)
        }
    }
    
    // MARK: - Primitive View
    
    private var primitiveView: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 12) // Placeholder for chevron alignment
            
            if let key = key {
                Text("\(key):")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            Text(formattedValue)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(valueColor)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.leading, indentation)
    }
    
    // MARK: - Value Formatting
    
    private var formattedValue: String {
        if let string = value as? String {
            return "\"\(string)\""
        } else if let number = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                return number.boolValue ? "true" : "false"
            }
            return "\(number)"
        } else if value is NSNull {
            return "null"
        } else {
            return String(describing: value)
        }
    }
    
    private var valueColor: Color {
        if value is String {
            return .green
        } else if let number = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                return .blue
            }
            return .orange
        } else if value is NSNull {
            return .gray
        }
        return .primary
    }
}

// MARK: - JSON Parsing Helper

extension String {
    /// Attempts to parse the string as JSON and returns the parsed object
    func parseAsJSON() -> Any? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
    
    /// Returns true if this string appears to be JSON (starts with { or [)
    var looksLikeJSON: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }
}
