import SwiftUI

struct LogsViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> LogsViewController {
        let vc = LogsViewController()
        vc.viewModel = LogsViewModel()
        vc.viewModel.register()
        return vc
    }
    func updateNSViewController(_ nsViewController: LogsViewController, context: Context) {}
}
