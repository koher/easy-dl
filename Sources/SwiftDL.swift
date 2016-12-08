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
        
        func download(_ items: [Item]) {
            self.bytesDownloaded = 0
            
            self.download(items[0..<items.count]) { error in
                if let error = error {
                    self.complete(with: .failure(error))
                    return
                }
                
                self.complete(with: .success)
            }
        }

        if needsPreciseProgress {
            contentLength(of: items[0..<items.count]) { length, error, itemsToDownload in
                if let error = error {
                    self.complete(with: .failure(error))
                    return
                }
                
                self.bytesExpectedToDownload = length
                
                download(itemsToDownload)
            }
        } else {
            download(items)
        }
    }
    
    private func contentLength(of items: ArraySlice<Item>, _ callback: @escaping (Int64?, Error?, [Item]) -> ()) {
        guard let first = items.first else {
            DispatchQueue.main.async {
                callback(0, nil, [])
            }
            return
        }
        
        contentLength(of: first) { length, error, cached in
            if let error = error {
                callback(nil, error, [])
                return
            }
            
            let tail = items[(items.startIndex + 1)..<items.endIndex]
            guard let headLength = length else {
                callback(nil, nil, Array(tail))
                return
            }
            
            self.contentLength(of: tail) { length, error, itemsToDownload in
                if let error = error {
                    callback(nil, error, [])
                    return
                }
                
                guard let tailLength = length else {
                    callback(nil, nil, [first] + itemsToDownload)
                    return
                }
                
                callback(headLength + tailLength, nil, cached ? itemsToDownload : [first] + itemsToDownload)
            }
        }
    }
    
    private func contentLength(of item: Item, _ callback: @escaping (Int64?, Error?, Bool) -> ()) {
        let request = NSMutableURLRequest(url: item.url)
        request.httpMethod = "HEAD"
        commonRequestHeaders?.forEach {
            request.setValue($0.1, forHTTPHeaderField: $0.0)
        }
        if let ifModifiedSince = item.ifModifiedSince {
            request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
        session.dataTask(with: request as URLRequest) { _, response, error in
            if let error = error {
                callback(nil, error, false)
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                callback(nil, nil, false)
                return
            }
            
            if response.statusCode == 304 {
                callback(0, nil, true)
                return
            }
            
            let contentLength = response.expectedContentLength
            guard contentLength != -1 else { // `-1` because no `NSURLResponseUnknownLength` in Swift
                callback(nil, nil, false)
                return
            }
            
            callback(contentLength, nil, false)
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
        if let ifModifiedSince = item.ifModifiedSince {
            request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
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
        
        internal var modificationDate: Date? {
            return (try? FileManager.default.attributesOfItem(atPath: destination))?[FileAttributeKey.modificationDate] as? Date
        }
        
        internal var ifModifiedSince: String? {
            return modificationDate.map { Downloader.dateFormatter.string(from: $0) }
        }
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

            let response = (downloadTask.response as? HTTPURLResponse)!
            if response.statusCode == 304 {
                callback(nil)
                return
            }
            
            let fileManager = FileManager.default
            try? fileManager.removeItem(atPath: item.destination) // OK though it fails if the file does not exists
            do {
                try fileManager.moveItem(at: location, to: URL(fileURLWithPath: item.destination))
                if let lastModified = response.allHeaderFields["Last-Modified"] as? String {
                    if let modificationDate = Downloader.dateFormatter.date(from: lastModified) {
                        try fileManager.setAttributes([.modificationDate: modificationDate], ofItemAtPath: item.destination)
                    }
                }
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
    
    static internal var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(abbreviation: "GMT")!
        return formatter
    }
}
