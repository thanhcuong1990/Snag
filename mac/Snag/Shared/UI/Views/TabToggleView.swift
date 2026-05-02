import SwiftUI

/// Network / Logs toggle in the window titlebar. Writes through to
/// `SnagController.route` but only switches between `.network` and `.logs`.
/// When the route is `.saved` or `.compose`, the toggle defaults to Network.
struct TabToggleView: View {
    @ObservedObject var controller = SnagController.shared
    @ObservedObject var languageManager = LanguageManager.shared

    private var binding: Binding<MainContentRoute> {
        Binding(
            get: { controller.route == .logs ? .logs : .network },
            set: { controller.route = $0 }
        )
    }

    var body: some View {
        Picker("", selection: binding) {
            Text("Network".localized).tag(MainContentRoute.network)
            Text("Logs".localized).tag(MainContentRoute.logs)
        }
        .pickerStyle(SegmentedPickerStyle())
        .frame(width: 150)
        .padding(.trailing, 8)
    }
}
