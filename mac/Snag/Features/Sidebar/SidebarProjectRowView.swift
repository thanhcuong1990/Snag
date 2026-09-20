import SwiftUI

struct SidebarProjectRowView: View {
    @ObservedObject var project: SnagProjectController
    @ObservedObject var snagController: SnagController = SnagController.shared
    @ObservedObject var settings: SettingsManager = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarProjectHeader(project: project)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visibleDevices, id: \.self) { device in
                    SidebarDeviceRow(
                        device: device,
                        isSelected: snagController.selectedProjectController == project && project.selectedDeviceController == device
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var visibleDevices: [SnagDeviceController] {
        guard settings.showOnlyLocalDevices else { return project.deviceControllers }
        let local = project.deviceControllers.filter { !LocalMachine.isRemote($0.hostMachine) }
        return local.isEmpty ? project.deviceControllers : local
    }
}
