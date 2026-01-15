import SwiftUI

struct TabToggleView: View {
    @ObservedObject var controller = SnagController.shared
    @ObservedObject var languageManager = LanguageManager.shared
    
    var body: some View {
        Picker("", selection: $controller.selectedTab) {
            Text("Network".localized).tag(SnagController.MainTab.network)
            Text("Logs".localized).tag(SnagController.MainTab.logs)
        }
        .pickerStyle(SegmentedPickerStyle())
        .frame(width: 150)
        .padding(.trailing, 8)
    }
}
