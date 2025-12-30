import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case auto
    case light
    case dark
    
    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .auto: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
    
    var helpText: String {
        switch self {
        case .auto: return "Style: Auto (System)"
        case .light: return "Style: Light"
        case .dark: return "Style: Dark"
        }
    }
}

struct AppearanceToggleView: View {
    @AppStorage(SnagConstants.appearanceModeKey) private var appearanceMode: AppearanceMode = .auto
    @State private var isHovering = false
    
    var body: some View {
        Button(action: nextAppearance) {
            Image(systemName: appearanceMode.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .background(isHovering ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(appearanceMode.helpText)
        .onAppear {
            applyAppearance()
        }
    }
    
    private func nextAppearance() {
        let allCases = AppearanceMode.allCases
        if let currentIndex = allCases.firstIndex(of: appearanceMode) {
            let nextIndex = (currentIndex + 1) % allCases.count
            appearanceMode = allCases[nextIndex]
            applyAppearance()
        }
    }
    
    private func applyAppearance() {
        if let name = appearanceMode.nsAppearanceName {
            NSApp.appearance = NSAppearance(named: name)
        } else {
            NSApp.appearance = nil
        }
    }
}
