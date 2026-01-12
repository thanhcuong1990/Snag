import SwiftUI
import AppKit

struct RightClickObserver: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

class RightClickView: NSView {
    var onRightClick: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        
        if window != nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                self?.handleRightClick(event: event)
                return event
            }
        }
    }
    
    private func handleRightClick(event: NSEvent) {
        guard let window = self.window else { return }
        
        // Convert window coordinate to view coordinate
        let pointInView = self.convert(event.locationInWindow, from: nil)
        
        // Check if the click is within our bounds
        if self.bounds.contains(pointInView) {
            // Did it happen in this window? (Local monitor covers app, check window match)
            if event.window == window {
                onRightClick?()
            }
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        self.background(RightClickObserver(onRightClick: action))
    }
}
