import Foundation
import ObjectiveC.runtime

protocol SnagConnectionInjectorDelegate: AnyObject {
    func connectionInjector(_ injector: SnagConnectionInjector, didStart urlConnection: NSURLConnection)
    func connectionInjector(_ injector: SnagConnectionInjector, didReceiveResponse urlConnection: NSURLConnection, response: URLResponse)
    func connectionInjector(_ injector: SnagConnectionInjector, didReceiveData urlConnection: NSURLConnection, data: Data)
    func connectionInjector(_ injector: SnagConnectionInjector, didFailWithError urlConnection: NSURLConnection, error: Error)
    func connectionInjector(_ injector: SnagConnectionInjector, didFinishLoading urlConnection: NSURLConnection)
}

class SnagConnectionInjector: NSObject {
    
    weak var delegate: SnagConnectionInjectorDelegate?
    
    init(delegate: SnagConnectionInjectorDelegate) {
        super.init()
        self.delegate = delegate
        self.inject()
    }
    
    private func inject() {
        let classCount = objc_getClassList(nil, 0)
        let classes = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(classCount))
        let autoreleasingClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(classes)
        let count = objc_getClassList(autoreleasingClasses, classCount)
        
        defer {
            classes.deallocate()
        }
        
        for i in 0..<Int(count) {
            let cls: AnyClass = classes[i]
            
            if class_conformsToProtocol(cls, NSURLConnectionDataDelegate.self) ||
               class_conformsToProtocol(cls, NSURLConnectionDelegate.self) {
                 swizzleConnectionDidReceiveResponse(cls)
                 swizzleConnectionDidReceiveData(cls)
                 swizzleConnectionDidFailWithError(cls)
                 swizzleConnectionDidFinishLoading(cls)
            }
        }
        
        swizzleConnectionStart()
    }
    
    typealias StartBlock = @convention(c) (AnyObject, Selector) -> Void
    typealias DidReceiveResponseBlock = @convention(c) (AnyObject, Selector, NSURLConnection, URLResponse) -> Void
    typealias DidReceiveDataBlock = @convention(c) (AnyObject, Selector, NSURLConnection, Data) -> Void
    typealias DidFailWithErrorBlock = @convention(c) (AnyObject, Selector, NSURLConnection, NSError) -> Void
    typealias DidFinishLoadingBlock = @convention(c) (AnyObject, Selector, NSURLConnection) -> Void
    
    private func swizzleConnectionStart() {
        guard let connectionClass = NSClassFromString("NSURLConnection") else { return }
        
        let initSelectors = [
            "initWithRequest:delegate:startImmediately:",
            "initWithRequest:delegate:"
        ]
        
        for selectorString in initSelectors {
            let selector = NSSelectorFromString(selectorString)
            guard let method = class_getInstanceMethod(connectionClass, selector) else { continue }
            
            let originalImp = method_getImplementation(method)
            
            if selectorString.contains("startImmediately:") {
                typealias InitWithStartBlock = @convention(c) (AnyObject, Selector, URLRequest, AnyObject?, Bool) -> AnyObject?
                let original = unsafeBitCast(originalImp, to: InitWithStartBlock.self)
                
                let block: @convention(block) (AnyObject, URLRequest, AnyObject?, Bool) -> AnyObject? = { [weak self] instance, request, delegate, startImmediately in
                    let connection = original(instance, selector, request, delegate, startImmediately) as? NSURLConnection
                    if let self = self, let connection = connection, startImmediately {
                        self.delegate?.connectionInjector(self, didStart: connection)
                    }
                    return connection
                }
                
                let newImp = imp_implementationWithBlock(block)
                method_setImplementation(method, newImp)
            } else {
                typealias InitBlock = @convention(c) (AnyObject, Selector, URLRequest, AnyObject?) -> AnyObject?
                let original = unsafeBitCast(originalImp, to: InitBlock.self)
                
                let block: @convention(block) (AnyObject, URLRequest, AnyObject?) -> AnyObject? = { [weak self] instance, request, delegate in
                    let connection = original(instance, selector, request, delegate) as? NSURLConnection
                    if let self = self, let connection = connection {
                        self.delegate?.connectionInjector(self, didStart: connection)
                    }
                    return connection
                }
                
                let newImp = imp_implementationWithBlock(block)
                method_setImplementation(method, newImp)
            }
        }
        
        let startSelector = NSSelectorFromString("start")
        if let startMethod = class_getInstanceMethod(connectionClass, startSelector) {
            let originalStartImp = method_getImplementation(startMethod)
            let originalStart = unsafeBitCast(originalStartImp, to: StartBlock.self)
            
            let startBlock: @convention(block) (AnyObject) -> Void = { [weak self] instance in
                if let self = self, let connection = instance as? NSURLConnection {
                    self.delegate?.connectionInjector(self, didStart: connection)
                }
                originalStart(instance, startSelector)
            }
            
            let newStartImp = imp_implementationWithBlock(startBlock)
            method_setImplementation(startMethod, newStartImp)
        }
    }

    private func swizzleConnectionDidReceiveResponse(_ cls: AnyClass) {
        let selectorString = "connection:didReceiveResponse:"
        let sel = Selector(selectorString)
        
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidReceiveResponseBlock.self)
        
        let block: @convention(block) (AnyObject, NSURLConnection, URLResponse) -> Void = { [weak self] (instance, connection, response) in
            if let self = self {
                self.delegate?.connectionInjector(self, didReceiveResponse: connection, response: response)
            }
            original(instance, sel, connection, response)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleConnectionDidReceiveData(_ cls: AnyClass) {
        let selectorString = "connection:didReceiveData:"
        let sel = Selector(selectorString)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidReceiveDataBlock.self)
        
        let block: @convention(block) (AnyObject, NSURLConnection, Data) -> Void = { [weak self] (instance, connection, data) in
            if let self = self {
                self.delegate?.connectionInjector(self, didReceiveData: connection, data: data)
            }
            original(instance, sel, connection, data)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleConnectionDidFailWithError(_ cls: AnyClass) {
        let selector = #selector(NSURLConnectionDelegate.connection(_:didFailWithError:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidFailWithErrorBlock.self)
        
        let block: @convention(block) (AnyObject, NSURLConnection, NSError) -> Void = { [weak self] (instance, connection, error) in
            if let self = self {
                self.delegate?.connectionInjector(self, didFailWithError: connection, error: error)
            }
            original(instance, selector, connection, error)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleConnectionDidFinishLoading(_ cls: AnyClass) {
        let selector = #selector(NSURLConnectionDataDelegate.connectionDidFinishLoading(_:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidFinishLoadingBlock.self)
        
        let block: @convention(block) (AnyObject, NSURLConnection) -> Void = { [weak self] (instance, connection) in
            if let self = self {
                self.delegate?.connectionInjector(self, didFinishLoading: connection)
            }
            original(instance, selector, connection)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
}
