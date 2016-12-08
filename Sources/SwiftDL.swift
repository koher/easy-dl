import Foundation

public class Downloader {
    public let items: [Item]
    public let commonRequestHeaders: [String: String]?
    
    private var progressHandlers: [(Int64, Int64?, Int, Int64, Int64?) -> ()] = []
    private var completionHandlers: [(Result) -> ()] = []

    private var bytesDownloaded: Int64! = nil
    private var bytesExpectedToDownload: Int64? = nil
    private var result: Result? = nil
    
    private var session: URLSession! = nil

    private var currentItemIndex: Int = 0
    private var currentItem: Item! = nil
    private var currentCallback: ((Error?) -> ())? = nil

    public init(items: [Item], needsPreciseProgress: Bool = true, commonRequestHeaders: [String: String]? = nil) {
        self.items = items
        self.commonRequestHeaders = commonRequestHeaders
        
        session = URLSession(configuration: .default, delegate: Delegate(downloader: self), delegateQueue: .main)
        
        let itemSlice = items[0..<items.count]
        
        func download() {
            self.bytesDownloaded = 0
            
            self.download(itemSlice) { error in
                if let error = error {
                    self.complete(with: .failure(error))
                    return
                }
                
                self.complete(with: .success)
            }
        }

        if needsPreciseProgress {
            contentLength(of: itemSlice) { length, error in
                if let error = error {
                    self.complete(with: .failure(error))
                    return
                }
                
                self.bytesExpectedToDownload = length
                
                download()
            }
        } else {
            download()
        }
    }
    
    private func contentLength(of items: ArraySlice<Item>, _ callback: @escaping (Int64?, Error?) -> ()) {
        guard let first = items.first else {
            DispatchQueue.main.async {
                callback(0, nil)
            }
            return
        }
        
        contentLength(of: first) { length, error in
            if let error = error {
                callback(nil, error)
                return
            }
            
            guard let headLength = length else {
                callback(nil, nil)
                return
            }
            
            self.contentLength(of: items[(items.startIndex + 1)..<items.endIndex]) { length, error in
                if let error = error {
                    callback(nil, error)
                }
                
                guard let tailLength = length else {
                    callback(nil, nil)
                    return
                }
                
                callback(headLength + tailLength, nil)
            }
        }
    }
    
    private func contentLength(of item: Item, _ callback: @escaping (Int64?, Error?) -> ()) {
        let request = NSMutableURLRequest(url: item.url)
        request.httpMethod = "HEAD"
        commonRequestHeaders?.forEach {
            request.setValue($0.1, forHTTPHeaderField: $0.0)
        }
        session.dataTask(with: request as URLRequest) { _, response, error in
            if let error = error {
                callback(nil, error)
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                callback(nil, nil)
                return
            }
            
            let contentLength = response.expectedContentLength
            guard contentLength != -1 else { // `-1` because no `NSURLResponseUnknownLength` in Swift
                callback(nil, nil)
                return
            }
            
            callback(contentLength, nil)
        }.resume()
    }
    
    private func download(_ items: ArraySlice<Item>, _ callback: @escaping (Error?) -> ()) {
        currentItemIndex = items.startIndex
        
        guard let first = items.first else {
            callback(nil)
            return
        }
        
        download(first) { error in
            if let error = error {
                callback(error)
                return
            }
            
            self.download(items[(items.startIndex + 1)..<items.endIndex]) { error in
                callback(error)
                return
            }
        }
    }
    
    private func download(_ item: Item, _ callback: @escaping (Error?) -> ()) {
        currentItem = item
        currentCallback = callback
        
        let request = NSMutableURLRequest(url: item.url)
        commonRequestHeaders?.forEach {
            request.setValue($0.1, forHTTPHeaderField: $0.0)
        }
        
        session.downloadTask(with: request as URLRequest).resume()
    }
    
    private func makeProgress(bytesDownloaded: Int64, totalBytesDownloadedForItem: Int64, totalBytesExpectedToDownloadForItem: Int64?) {
        self.bytesDownloaded! += bytesDownloaded
        progressHandlers.forEach {
            $0(self.bytesDownloaded, self.bytesExpectedToDownload, self.currentItemIndex, totalBytesDownloadedForItem, totalBytesExpectedToDownloadForItem)
        }
    }
    
    private func complete(with result: Result) {
        completionHandlers.forEach {
            $0(result)
        }
        
        self.result = result
        
        progressHandlers.removeAll()
        completionHandlers.removeAll()
        
        session = nil
        // `self` is released by this if it is not retained outside
        // because the `delegate` which retains `self` is released.
    }
    
    public func cancel() {
        // TODO
    }
    
    public func handleProgress(_ handler: @escaping (Int64, Int64?, Int, Int64, Int64?) -> ()) {
        DispatchQueue.main.async { [weak self] in
            if let zelf = self, let bytesDownloaded = zelf.bytesDownloaded {
                handler(bytesDownloaded, zelf.bytesExpectedToDownload, zelf.items.count, 0, 0)
            }
            guard let zelf = self, zelf.result == nil else {
                return
            }
            
            self?.progressHandlers.append(handler)
        }
    }
    
    public func handleCompletion(_ handler: @escaping (Result) -> ()) {
        DispatchQueue.main.async {
            if let result = self.result {
                handler(result)
                return
            }
            
            self.completionHandlers.append(handler)
        }
    }
    
    public struct Item {
        public var url: URL
        public var destination: String
    }
    
    public enum Result {
        case success
        case failure(Error)
    }
    
    private class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        let downloader: Downloader
        
        init(downloader: Downloader) {
            self.downloader = downloader
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                downloader.currentCallback!(error)
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let item = downloader.currentItem!
            let callback = downloader.currentCallback!
            
            do {
                let fileManager = FileManager.default
                try? fileManager.removeItem(atPath: item.destination)
                try fileManager.moveItem(at: location, to: URL(fileURLWithPath: item.destination))
                callback(nil)
            } catch let error {
                callback(error)
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            downloader.makeProgress(
                bytesDownloaded: bytesWritten,
                totalBytesDownloadedForItem: totalBytesWritten,
                totalBytesExpectedToDownloadForItem: totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
                    ? nil : totalBytesExpectedToWrite
            )
        }
    }
}
