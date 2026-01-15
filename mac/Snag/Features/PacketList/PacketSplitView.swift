import SwiftUI

struct PacketSplitView: View {
    @AppStorage(SnagConstants.packetsSplitRatioKey) private var packetsSplitRatio: Double = 0.5
    @State private var isDraggingPackets: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                PacketsViewControllerWrapper()
                    .frame(height: max(100, geometry.size.height * packetsSplitRatio))
                
                ResizableDivider(isDragging: $isDraggingPackets, orientation: .vertical)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingPackets = true
                                let newHeight = (geometry.size.height * packetsSplitRatio) + value.translation.height
                                let newRatio = newHeight / geometry.size.height
                                // Clamp ratio between 0.1 and 0.9
                                packetsSplitRatio = min(max(newRatio, 0.1), 0.9)
                            }
                            .onEnded { _ in
                                isDraggingPackets = false
                            }
                    )
                
                DetailViewControllerWrapper()
                    .frame(maxHeight: .infinity)
            }
        }
    }
}
