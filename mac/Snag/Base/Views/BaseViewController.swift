import Cocoa

class BaseViewController: NSViewController {

    override func loadView() {
        self.view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }
    
    static var identifier: NSStoryboard.SceneIdentifier {
        return NSStoryboard.SceneIdentifier(String(describing: self))
    }
    
    func setup() {
        
    }
}

