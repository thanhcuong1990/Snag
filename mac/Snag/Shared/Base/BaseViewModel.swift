import Cocoa
import Combine

@MainActor
class BaseViewModel: NSObject, ObservableObject {

    var onChange: (()->())?
    var cancellables = Set<AnyCancellable>()

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

