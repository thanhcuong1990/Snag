import Cocoa

class BaseViewModel: NSObject, ObservableObject {

    var onChange: (()->())?
}

