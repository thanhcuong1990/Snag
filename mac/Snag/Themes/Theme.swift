import Cocoa
import SwiftUI

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        return NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return dark
            } else {
                return light
            }
        }
    }
}

struct ThemeColor {
    static var textColor: NSColor {
        return NSColor.dynamic(light: .black, dark: .white)
    }
    
    static var labelColor: NSColor {
        return NSColor.dynamic(light: .black, dark: .white)
    }
    
    static var secondaryLabelColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#8E8E93"), dark: NSColor(hex: "#98989D"))
    }
    
    static var controlBackgroundColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#F2F2F7"), dark: NSColor(hex: "#2C2C2E"))
    }
    
    static var gridColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#E5E5EA"), dark: NSColor(hex: "#38383A"))
    }
    
    static var separatorColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#E5E5EA"), dark: NSColor(hex: "#38383A"))
    }
    
    static var contentBarColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#FFFFFF"), dark: NSColor(hex: "#1C1C1E"))
    }
    
    static var rowSelectedColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#007AFF"), dark: NSColor(hex: "#007AFF"))
    }
    
    static var statusGreenColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#28CD41"), dark: NSColor(hex: "#30D158"))
    }
    
    static var statusOrangeColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#FF9500"), dark: NSColor(hex: "#FF9F0A"))
    }
    
    static var statusRedColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#FF3B30"), dark: NSColor(hex: "#FF453A"))
    }
    
    static var projectListBackgroundColor: NSColor {
        return NSColor(hex: "#232323")
    }
    
    static var projectTextColor: NSColor {
        return NSColor(hex: "#ffffff")
    }
    
    static var deviceListBackgroundColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#F2F2F7"), dark: NSColor(hex: "#1C1C1E"))
    }
    
    static var deviceRowSelectedColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#E5E5EA"), dark: NSColor(hex: "#2C2C2E"))
    }
    
    static var packetListAndDetailBackgroundColor: NSColor {
        return NSColor.dynamic(light: .white, dark: NSColor(hex: "#1E1E1E"))
    }
    
    static var packetListAlternateBackgroundColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#F5F5F7"), dark: NSColor(hex: "#242424"))
    }
    
    static var urlTextColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#646464"), dark: .white)
    }
    
    static var httpMethodGetColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#007AFF"), dark: NSColor(hex: "#0A84FF"))
    }
    
    static var httpMethodPostColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#34C759"), dark: NSColor(hex: "#30D158"))
    }
    
    static var httpMethodDeleteColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#FF3B30"), dark: NSColor(hex: "#FF453A"))
    }
    
    static var httpMethodPutColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#AF52DE"), dark: NSColor(hex: "#BF5AF2"))
    }
    
    static var httpMethodPatchColor: NSColor {
        return NSColor.dynamic(light: NSColor(hex: "#FF9500"), dark: NSColor(hex: "#FF9F0A"))
    }
    
    static var httpMethodDefaultColor: NSColor {
        return secondaryLabelColor
    }
}

// SwiftUI support
extension Color {
    init(nsColor: NSColor) {
        self.init(nsColor)
    }
    
    static var controlBackgroundColor: Color { Color(nsColor: ThemeColor.controlBackgroundColor) }
    static var packetListAndDetailBackgroundColor: Color { Color(nsColor: ThemeColor.packetListAndDetailBackgroundColor) }
    static var packetListAlternateBackgroundColor: Color { Color(nsColor: ThemeColor.packetListAlternateBackgroundColor) }
    static var labelColor: Color { Color(nsColor: ThemeColor.labelColor) }
    static var secondaryLabelColor: Color { Color(nsColor: ThemeColor.secondaryLabelColor) }
    static var urlTextColor: Color { Color(nsColor: ThemeColor.urlTextColor) }
    
    static var statusGreen: Color { Color(nsColor: ThemeColor.statusGreenColor) }
    static var statusOrange: Color { Color(nsColor: ThemeColor.statusOrangeColor) }
    static var statusRed: Color { Color(nsColor: ThemeColor.statusRedColor) }
    
    static var methodGet: Color { Color(nsColor: ThemeColor.httpMethodGetColor) }
    static var methodPost: Color { Color(nsColor: ThemeColor.httpMethodPostColor) }
    static var methodDelete: Color { Color(nsColor: ThemeColor.httpMethodDeleteColor) }
    static var methodPut: Color { Color(nsColor: ThemeColor.httpMethodPutColor) }
    static var methodPatch: Color { Color(nsColor: ThemeColor.httpMethodPatchColor) }
}
