
import SwiftUI

@MainActor
class DevicesViewModelWrapper: ObservableObject {
    @Published var items: [SnagDeviceController] = []
    @Published var selectedItemIndex: Int? = nil

    private var viewModel: DevicesViewModel?

    init(viewModel: DevicesViewModel?) {
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

struct DeviceItemView: View {
    let deviceName: String
    let deviceDescription: String
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: ThemeColor.deviceRowSelectedColor))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(isSelected ? Font.system(size: 14).weight(.medium) : Font.system(size: 14))
                    .foregroundColor(Color(nsColor: isSelected ? ThemeColor.textColor : ThemeColor.secondaryLabelColor))
                
                Text(deviceDescription)
                    .font(Font.system(size: 10))
                    .foregroundColor(Color(nsColor: ThemeColor.secondaryLabelColor))
            }
            .padding(.horizontal, 15)
        }
        .frame(height: 60)
        .padding(.horizontal, 10)
    }
}

struct DevicesView: View {
    @ObservedObject var viewModelWrapper: DevicesViewModelWrapper
    var onDeviceSelect: (SnagDeviceController) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(viewModelWrapper.items.enumerated()), id: \.offset) { index, item in
                    DeviceItemView(
                        deviceName: item.deviceName ?? "",
                        deviceDescription: item.deviceDescription ?? "",
                        isSelected: viewModelWrapper.selectedItemIndex == index
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDeviceSelect(item)
                    }
                }
            }
            .padding(.top, 30)
        }
        .background(Color(nsColor: ThemeColor.deviceListBackgroundColor))
    }
}
