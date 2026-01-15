import Cocoa

class BaseTableView: NSTableView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    func makeView<T>(withOwner: Any?) -> T? {
        
        return self.makeView(withIdentifier: .init(String(describing: T.self)), owner: nil) as? T
    }
}
