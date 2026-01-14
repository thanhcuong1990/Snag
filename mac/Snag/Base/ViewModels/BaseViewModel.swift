import Cocoa

@MainActor
class BaseViewModel: NSObject, ObservableObject {

    var onChange: (()->())?
}

