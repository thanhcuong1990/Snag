import SwiftUI

struct DetailViewControllerWrapper: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> DetailViewController {
        let vc = DetailViewController()
        vc.viewModel = DetailViewModel()
        vc.viewModel?.register()
        return vc
    }
    func updateNSViewController(_ nsViewController: DetailViewController, context: Context) {}
}
