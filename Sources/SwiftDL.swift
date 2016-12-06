import Foundation

public class Downloader {
    public let items: [Item]
    
    private var progressHandlers: [(Int64, Int64?) -> ()] = []
    private var completionHandlers: [(Result) -> ()] = []

    private var bytesDownloaded: Int64? = nil
    private var bytesExpectedToDownload: Int64? = nil
    private var result: Result? = nil
    
    private var session: URLSession! = nil

    private var currentItem: Item! = nil
    private var currentCallback: ((Error?) -> ())? = nil

    public init(items: [Item], needsPreciseProgress: Bool = true) {
        self.items = items
        
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
        session.dataTask(with: request as URLRequest) { _, response, error in
            if let error = error {
                callback(nil, error)
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                callback(nil, nil)
                return
            }
            
            guard let contentLengthString = response.allHeaderFields["Content-Length"] as? String else {
                callback(nil, nil)
                return
            }
            
            guard let contentLength = Int64(contentLengthString) else {
                callback(nil, nil)
                return
            }
            
            callback(contentLength, nil)
        }.resume()
    }
    
    private func download(_ items: ArraySlice<Item>, _ callback: @escaping (Error?) -> ()) {
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
        session.downloadTask(with: item.url).resume()
    }
    
    private func makeProgress(bytesDownloaded: Int64) {
        self.bytesDownloaded! += bytesDownloaded
        progressHandlers.forEach {
            $0(self.bytesDownloaded!, self.bytesExpectedToDownload)
        }
    }
    
    private func complete(with result: Result) {
        completionHandlers.forEach {
            $0(result)
        }
        
        self.result = result
        
        session = nil
        
        progressHandlers.removeAll()
        completionHandlers.removeAll()
    }
    
    public func cancel() {
        // TODO
    }
    
    public func handleProgress(_ handler: @escaping (Int64, Int64?) -> ()) {
        DispatchQueue.main.async { [weak self] in
            if let bytesDownloaded = self?.bytesDownloaded {
                handler(bytesDownloaded, self?.bytesExpectedToDownload)
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
            downloader.makeProgress(bytesDownloaded: bytesWritten)
        }
    }
}
