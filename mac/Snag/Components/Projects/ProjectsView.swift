import SwiftUI

struct ProjectItemView: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 139/255, green: 92/255, blue: 246/255))
            }
            Text(title)
                .font(isSelected ? Font.system(size: 14).weight(.medium) : Font.system(size: 14))
                .foregroundColor(Color(nsColor: isSelected ? ThemeColor.projectTextColor : ThemeColor.secondaryLabelColor))
                .padding(.horizontal, 10)
                .lineLimit(1)
        }
        .frame(height: 40)
        .padding(.horizontal, 5)
    }
}

struct ProjectsView: View {
    @ObservedObject var viewModelWrapper: ProjectsViewModelWrapper
    var onProjectSelect: (SnagProjectController) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(viewModelWrapper.items.enumerated()), id: \.offset) { index, item in
                    ProjectItemView(
                        title: item.projectName ?? "",
                        isSelected: viewModelWrapper.selectedItemIndex == index
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onProjectSelect(item)
                    }
                }
            }
            .padding(.top, 30)
        }
        .background(Color(nsColor: ThemeColor.projectListBackgroundColor))
    }
}

class ProjectsViewModelWrapper: ObservableObject {
    @Published var items: [SnagProjectController] = []
    @Published var selectedItemIndex: Int? = nil
    
    private var viewModel: ProjectsViewModel?
    
    init(viewModel: ProjectsViewModel?) {
        self.viewModel = viewModel
        self.update()
        
        viewModel?.onChange = { [weak self] in
            self?.update()
        }
    }
    
    func update() {
        self.items = viewModel?.items ?? []
        self.selectedItemIndex = viewModel?.selectedItemIndex
    }
}
