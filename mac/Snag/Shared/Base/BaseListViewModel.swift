import Cocoa

class BaseListViewModel<T>: BaseViewModel {

    var items = [T]()
    
    func set(items: [T])
    {
        self.items = items
        self.onChange?()
    }
    
    func itemCount() -> Int
    {
        return self.items.count
    }
    
    func item(at: Int) -> T?
    {
        return self.items[at]
    }
    
}
