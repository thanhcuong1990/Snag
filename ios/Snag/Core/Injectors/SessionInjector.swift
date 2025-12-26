import Foundation
import ObjectiveC.runtime

protocol SnagSessionInjectorDelegate: AnyObject {
    func sessionInjector(_ injector: SnagSessionInjector, didStart dataTask: URLSessionTask)
    func sessionInjector(_ injector: SnagSessionInjector, didReceiveResponse dataTask: URLSessionTask, response: URLResponse)
    func sessionInjector(_ injector: SnagSessionInjector, didReceiveData dataTask: URLSessionTask, data: Data)
    func sessionInjector(_ injector: SnagSessionInjector, didFinishWithError dataTask: URLSessionTask, error: Error?)
}

class SnagSessionInjector: NSObject {
    
    weak var delegate: SnagSessionInjectorDelegate?
    
    init(delegate: SnagSessionInjectorDelegate) {
        super.init()
        self.delegate = delegate
        self.inject()
    }
    
    func inject() {
        var sessionClass: AnyClass? = NSClassFromString("__NSCFURLLocalSessionConnection")
        let privateTaskClass: AnyClass? = NSClassFromString("__NSCFURLSessionTask")
        
        if sessionClass == nil {
            sessionClass = NSClassFromString("__NSCFURLSessionConnection")
        }
        
        if let sessionClass = sessionClass {
            swizzleSessionDidReceiveData(sessionClass)
            swizzleSessionDidReceiveResponse(sessionClass)
            swizzleSessionDidFinishWithError(sessionClass)
        }
        
        swizzleSessionTaskResume(URLSessionTask.self)
        
        if let privateTaskClass = privateTaskClass {
            swizzleSessionTaskResume(privateTaskClass)
        }
    }
    
    typealias ResumeBlock = @convention(c) (AnyObject, Selector) -> Void
    typealias DidReceiveResponseBlock = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
    typealias DidReceiveResponseRewriteBlock = @convention(c) (AnyObject, Selector, AnyObject, Bool, Bool) -> Void
    typealias DidReceiveDataBlock = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    typealias DidFinishWithErrorBlock = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    private func swizzleSessionTaskResume(_ cls: AnyClass) {
        let selector = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: ResumeBlock.self)
        
        let block: @convention(block) (AnyObject) -> Void = { [weak self] (instance) in
            guard let self = self else { return }
            
            if let task = instance as? URLSessionTask {
                self.delegate?.sessionInjector(self, didStart: task)
            }
            
            original(instance, selector)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleSessionDidReceiveResponse(_ cls: AnyClass) {
         if #available(iOS 13.0, *) {
             let selector = NSSelectorFromString("_didReceiveResponse:sniff:rewrite:")
             guard let method = class_getInstanceMethod(cls, selector) else { return }
             
             let originalImp = method_getImplementation(method)
             let original = unsafeBitCast(originalImp, to: DidReceiveResponseRewriteBlock.self)
             
             let block: @convention(block) (AnyObject, AnyObject, Bool, Bool) -> Void = { [weak self] (instance, response, sniff, rewrite) in
                 guard let self = self else { return }
                 
                 if let task = instance.value(forKey: "task") as? URLSessionTask, let urlResponse = response as? URLResponse {
                     self.delegate?.sessionInjector(self, didReceiveResponse: task, response: urlResponse)
                 }
                 
                 original(instance, selector, response, sniff, rewrite)
             }
             
             let newImp = imp_implementationWithBlock(block)
             method_setImplementation(method, newImp)
             return
         }
        
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidReceiveResponseBlock.self)
        
        let block: @convention(block) (AnyObject, AnyObject, Bool) -> Void = { [weak self] (instance, response, sniff) in
            guard let self = self else { return }
            
            if let task = instance.value(forKey: "task") as? URLSessionTask, let urlResponse = response as? URLResponse {
                self.delegate?.sessionInjector(self, didReceiveResponse: task, response: urlResponse)
            }
            
            original(instance, selector, response, sniff)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleSessionDidReceiveData(_ cls: AnyClass) {
        let selector = NSSelectorFromString("_didReceiveData:")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidReceiveDataBlock.self)
        
        let block: @convention(block) (AnyObject, AnyObject) -> Void = { [weak self] (instance, dataObj) in
            guard let self = self else { return }
            
            if let task = instance.value(forKey: "task") as? URLSessionTask, let data = dataObj as? Data {
                self.delegate?.sessionInjector(self, didReceiveData: task, data: data)
            }
            
            original(instance, selector, dataObj)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private func swizzleSessionDidFinishWithError(_ cls: AnyClass) {
        let selector = NSSelectorFromString("_didFinishWithError:")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        
        let originalImp = method_getImplementation(method)
        let original = unsafeBitCast(originalImp, to: DidFinishWithErrorBlock.self)
        
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { [weak self] (instance, errorObj) in
            guard let self = self else { return }
            
            if let task = instance.value(forKey: "task") as? URLSessionTask {
                let error = errorObj as? Error
                self.delegate?.sessionInjector(self, didFinishWithError: task, error: error)
            }
            
            original(instance, selector, errorObj)
        }
        
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
}
