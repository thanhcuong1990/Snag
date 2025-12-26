import AppKit
import SwiftUI

enum DetailsTheme {
    static func jsonViewerBackgroundNSColor() -> NSColor {
        return NSColor.dynamic(
            light: .white,
            dark: NSColor(srgbRed: 40/255, green: 40/255, blue: 40/255, alpha: 1)
        )
    }
    
    static var backgroundColor: Color {
        Color(nsColor: jsonViewerBackgroundNSColor())
    }
    
    // Proxyman-style orange accent color
    static let accentOrange = Color(red: 232/255, green: 85/255, blue: 53/255)
}
