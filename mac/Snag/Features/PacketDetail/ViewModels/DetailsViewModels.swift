import Foundation
import Combine
import SwiftUI

@MainActor
class DetailViewModelWrapper: ObservableObject {
    @Published var packet: SnagPacket?
    
    private var viewModel: DetailViewModel?
    
    init(viewModel: DetailViewModel?) {
        self.viewModel = viewModel
        self.packet = viewModel?.packet
        
        viewModel?.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.packet = self?.viewModel?.packet
            }
        }
    }
}

class OverviewViewModel: BaseViewModel {
    @Published var overviewRepresentation: ContentRepresentation?
    @Published var curlRepresentation: ContentRepresentation?
    @Published var isLoading: Bool = false
    private var parseTask: Task<Void, Never>?
    
    func register() {
         NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectPacket, object: nil)
         NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
         NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectSavedPacket, object: nil)
    }
    
    @objc func didSelectPacket() {
        self.update()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.currentSelectedPacket,
           packet.packetId == selectedPacket.packetId {
            self.update()
        }
    }
    
    func update() {
        parseTask?.cancel()
        
        guard let packet = SnagController.shared.currentSelectedPacket,
              let requestInfo = packet.requestInfo else {
            self.overviewRepresentation = nil
            self.curlRepresentation = nil
            self.isLoading = false
            self.onChange?()
            return
        }
        
        self.isLoading = true
        
        parseTask = Task {
            if Task.isCancelled { return }
            
            // Move expensive generation to detached task
            let (overview, curl) = await Task.detached(priority: .userInitiated) {
                let overview = ContentRepresentationParser.overviewRepresentation(requestInfo: requestInfo)
                let curl = CURLRepresentation(requestInfo: requestInfo)
                return (overview, curl)
            }.value
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.overviewRepresentation = overview
                    self.curlRepresentation = curl
                    self.isLoading = false
                    self.onChange?()
                }
            }
        }
    }
    
    func copyTextToClipboard() { overviewRepresentation?.copyToClipboard() }
    func copyCURLToClipboard() { curlRepresentation?.copyToClipboard() }
}

class KeyValueViewModel: BaseViewModel {
    @Published var items: [KeyValue] = []
    @Published var keyValueRepresentation: KeyValueRepresentation?
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectSavedPacket, object: nil)
    }
    
    @objc func didSelectPacket() {
        self.update()
        self.onChange?()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.currentSelectedPacket,
           packet.packetId == selectedPacket.packetId {
            self.update()
            self.onChange?()
        }
    }
    
    func update() { }
    
    func copyToClipboard() { keyValueRepresentation?.copyToClipboard() }
}

class RequestHeadersViewModel: KeyValueViewModel {
    override func update() {
        if let packet = SnagController.shared.currentSelectedPacket {
            self.items = packet.requestInfo?.requestHeaders?.toKeyValueArray() ?? []
            self.keyValueRepresentation = ContentRepresentationParser.keyValueRepresentation(dictionary: packet.requestInfo?.requestHeaders ?? [:])
        } else {
            self.items = []
            self.keyValueRepresentation = nil
        }
    }
}

class RequestParametersViewModel: KeyValueViewModel {
    override func update() {
        if let packet = SnagController.shared.currentSelectedPacket {
            if let urlString = packet.requestInfo?.url, let url = URL(string: urlString) {
                self.items = url.toKeyValueArray()
                self.keyValueRepresentation = ContentRepresentationParser.keyValueRepresentation(url: url)
            } else {
                self.items = []
                self.keyValueRepresentation = nil
            }
        } else {
            self.items = []
            self.keyValueRepresentation = nil
        }
    }
}

class ResponseHeadersViewModel: KeyValueViewModel {
    override func update() {
        if let packet = SnagController.shared.currentSelectedPacket {
            self.items = packet.requestInfo?.responseHeaders?.toKeyValueArray() ?? []
            self.keyValueRepresentation = ContentRepresentationParser.keyValueRepresentation(dictionary: packet.requestInfo?.responseHeaders ?? [:])
        } else {
            self.items = []
            self.keyValueRepresentation = nil
        }
    }
}

class DataViewModel: BaseViewModel {
    @Published var dataRepresentation: DataRepresentation?
    @Published var isLoading: Bool = false
    private var parseTask: Task<Void, Never>?
    
    func performUpdate(with data: Data?) {
        // Cancel any existing task
        parseTask?.cancel()
        
        guard let data = data else {
            self.dataRepresentation = nil
            self.isLoading = false
            return
        }
        
        // Start loading
        self.isLoading = true
        self.dataRepresentation = nil
        
        parseTask = Task {
            // Check if task was cancelled before starting work
            if Task.isCancelled { return }
            
            let result = await ContentRepresentationParser.dataRepresentationAsync(data: data)
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.dataRepresentation = result
                    self.isLoading = false
                    // Force UI refresh if needed
                    self.objectWillChange.send()
                    self.onChange?()
                }
            }
        }
    }

    func performUpdate(withBase64 base64String: String?) {
        // Cancel any existing task
        parseTask?.cancel()
        
        guard let base64String = base64String, !base64String.isEmpty else {
            self.dataRepresentation = nil
            self.isLoading = false
            return
        }
        
        // Start loading
        self.isLoading = true
        self.dataRepresentation = nil
        
        parseTask = Task {
            // Check if task was cancelled before starting work
            if Task.isCancelled { return }
            
            // Move Base64 decoding off the main thread
            let result = await Task.detached(priority: .userInitiated) { () -> DataRepresentation? in
                guard let data = base64String.base64Data else { return nil }
                return await DataRepresentationParser.parseAsync(data: data)
            }.value
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.dataRepresentation = result
                    self.isLoading = false
                    // Force UI refresh if needed
                    self.objectWillChange.send()
                    self.onChange?()
                }
            }
        }
    }
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectSavedPacket, object: nil)
    }
    
    @objc func didSelectPacket() {
        self.update()
        self.onChange?()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.currentSelectedPacket,
           packet.packetId == selectedPacket.packetId {
            self.update()
            self.onChange?()
        }
    }
    
    func update() { }
    
    func copyToClipboard() {
        dataRepresentation?.copyToClipboard()
    }
}

class RequestBodyViewModel: DataViewModel {
    override func update() {
        if let packet = SnagController.shared.currentSelectedPacket {
            self.performUpdate(withBase64: packet.requestInfo?.requestBody)
        } else {
            self.performUpdate(withBase64: nil)
        }
    }
}

class ResponseDataViewModel: DataViewModel {
    override func update() {
        if let packet = SnagController.shared.currentSelectedPacket {
            self.performUpdate(withBase64: packet.requestInfo?.responseData)
        } else {
            self.performUpdate(withBase64: nil)
        }
    }
}
