import SwiftUI

struct TabToggleView: View {
    @ObservedObject var controller = SnagController.shared
    
    var body: some View {
        Picker("", selection: $controller.selectedTab) {
            Text("Network").tag(SnagController.MainTab.network)
            Text("Logs").tag(SnagController.MainTab.logs)
        }
        .pickerStyle(SegmentedPickerStyle())
        .frame(width: 150)
        .padding(.trailing, 8)
    }
}
