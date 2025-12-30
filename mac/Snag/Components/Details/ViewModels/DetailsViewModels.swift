import Foundation
import Combine
import SwiftUI

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
    
    func register() {
         NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectPacket, object: nil)
         NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
    }
    
    @objc func didSelectPacket() {
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket {
            self.overviewRepresentation = ContentRepresentationParser.overviewRepresentation(requestInfo: packet.requestInfo!)
            self.curlRepresentation = CURLRepresentation(requestInfo: packet.requestInfo)
        } else {
            self.overviewRepresentation = nil
            self.curlRepresentation = nil
        }
        self.onChange?()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket,
           packet.packetId == selectedPacket.packetId {
            self.overviewRepresentation = ContentRepresentationParser.overviewRepresentation(requestInfo: packet.requestInfo!)
            self.curlRepresentation = CURLRepresentation(requestInfo: packet.requestInfo)
            self.onChange?()
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
    }
    
    @objc func didSelectPacket() {
        self.update()
        self.onChange?()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket,
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
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket {
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
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket {
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
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket {
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
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.performUpdate(with: data)
            }
            return
        }

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
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.didSelectPacket), name: SnagNotifications.didSelectPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
    }
    
    @objc func didSelectPacket() {
        self.update()
        self.onChange?()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket,
           let selectedPacket = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket,
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
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket,
           let data = packet.requestInfo?.requestBody?.base64Data {
            self.performUpdate(with: data)
        } else {
            self.performUpdate(with: nil)
        }
    }
}

class ResponseDataViewModel: DataViewModel {
    override func update() {
        if let packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket,
           let data = packet.requestInfo?.responseData?.base64Data {
            self.performUpdate(with: data)
        } else {
            self.performUpdate(with: nil)
        }
    }
}
