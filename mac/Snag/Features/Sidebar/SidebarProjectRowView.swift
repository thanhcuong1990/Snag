import SwiftUI

struct SidebarProjectRowView: View {
    @ObservedObject var project: SnagProjectController
    @ObservedObject var snagController: SnagController = SnagController.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarProjectHeader(project: project)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(project.deviceControllers, id: \.self) { device in
                    SidebarDeviceRow(
                        device: device,
                        isSelected: snagController.selectedProjectController == project && project.selectedDeviceController == device
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
