import Cocoa
import SwiftUI

enum DetailType: Int {
    case overview = 0
    case requestHeaders = 1
    case requestParameters = 2
    case requestBody = 3
    case responseHeaders = 4
    case responseBody = 5
    case curl = 6
}

class DetailViewController: BaseViewController {

    var viewModel: DetailViewModel?
    
    private var hostingView: NSHostingView<DetailsView>?
    
    override func setup() {
        
        guard let viewModel = self.viewModel else { return }
        
        let detailsView = DetailsView(viewModelWrapper: DetailViewModelWrapper(viewModel: viewModel))
        
        let hostingView = NSHostingView(rootView: detailsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: self.view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        
        self.hostingView = hostingView
    }
}

