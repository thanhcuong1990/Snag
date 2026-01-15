import Cocoa
import SwiftUI

class ProjectsViewController: BaseViewController {
    
    var viewModel: ProjectsViewModel?
    var onProjectSelect : ((SnagProjectController) -> ())?
    
    private var hostingView: NSHostingView<ProjectsView>?
    
    override func setup() {
        
        guard let viewModel = self.viewModel else { return }
        
        let projectsView = ProjectsView(viewModelWrapper: ProjectsViewModelWrapper(viewModel: viewModel), onProjectSelect: { [weak self] item in
            self?.onProjectSelect?(item)
        })
        
        let hostingView = NSHostingView(rootView: projectsView)
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
