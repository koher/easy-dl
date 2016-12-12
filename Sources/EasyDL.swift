import Foundation

private typealias Cached = Bool

public class Downloader {
    public let items: [Item]
    public let needsPreciseProgress: Bool
    public let commonStrategy: Strategy
    public let commonRequestHeaders: [String: String]?
    
    private var progressHandlers: [(Int64, Int64?, Int, Int64, Int64?) -> ()] = []
    private var completionHandlers: [(Result) -> ()] = []

    private var bytesDownloaded: Int64! = nil
    private var bytesExpectedToDownload: Int64? = nil
    private var bytesDownloadedForItem: Int64! = nil
    private var bytesExpectedToDownloadForItem: Int64? = nil
    private var result: Result? = nil
    
    private var session: URLSession! = nil

    private var currentItemIndex: Int = 0
    private var currentItem: Item! = nil
    private var currentCallback: ((Result) -> ())? = nil
    private var currentTask: URLSessionTask? = nil
    
    private var canceled: Bool = false

    public init(
        items: [Item],
        needsPreciseProgress: Bool = true,
        commonStrategy: Strategy = .ifUpdated,
        commonRequestHeaders: [String: String]? = nil
    ) {
        self.items = items
        self.needsPreciseProgress = needsPreciseProgress
        self.commonStrategy = commonStrategy
        self.commonRequestHeaders = commonRequestHeaders
        
        session = URLSession(configuration: .default, delegate: Delegate(downloader: self), delegateQueue: .main)
        
        func download(_ cached: [Cached]) {
            assert(items.count == cached.count) // Always true for `Downloader` without bugs
            self.download(ArraySlice(zip(items, cached)), self.complete(with:))
        }

        if needsPreciseProgress {
            contentLength(of: items[0..<items.count]) { result in
                switch result {
                case .canceled:
                    self.complete(with: .cancel)
                case let .failure(error):
                    self.complete(with: .failure(error))
                case let .success(length, cached):
                    self.bytesExpectedToDownload = length
                    download(cached)
                }
            }
        } else {
            download([Cached](repeating: false, count: items.count))
        }
    }
    
    private func contentLength(of items: ArraySlice<Item>, _ callback: @escaping (ContentLengthResult) -> ()) {
        guard let first = items.first else {
            DispatchQueue.main.async {
                callback(.success(0, []))
            }
            return
        }
        
        contentLength(of: first) { result in
            switch result {
            case .canceled, .failure:
                callback(result)
            case let .success(headLength, headCached):
                let tail = items[(items.startIndex + 1)..<items.endIndex]
                guard let headLength = headLength else {
                    callback(.success(nil, headCached + [Cached](repeating: false, count: items.count - 1)))
                    break
                }
                
                self.contentLength(of: tail) { result in
                    switch result {
                    case .canceled, .failure:
                        callback(result)
                    case let .success(tailLength, tailCached):
                        guard let tailLength = tailLength else {
                            callback(.success(nil, headCached + tailCached))
                            break
                        }
                        
                        callback(.success(headLength + tailLength, headCached + tailCached))
                    }
                }
            }
        }
    }
    
    private func contentLength(of item: Item, _ callback: @escaping (ContentLengthResult) -> ()) {
        guard !canceled else {
            callback(.canceled)
            return
        }
        
        let request = NSMutableURLRequest(url: item.url)
        request.httpMethod = "HEAD"
        commonRequestHeaders?.forEach {
            request.setValue($0.1, forHTTPHeaderField: $0.0)
        }
        switch item.strategy ?? commonStrategy {
        case .always:
            break
        case .ifUpdated:
            if let ifModifiedSince = item.ifModifiedSince {
                request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
            }
        case .ifNotCached:
            callback(.success(0, [true]))
            return
        }
        let task = session.dataTask(with: request as URLRequest) { _, response, error in
            if self.canceled {
                callback(.canceled)
                return
            }
            
            if let error = error {
                callback(.failure(error))
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                callback(.success(nil, [false]))
                return
            }
            
            if response.statusCode == 304 {
                callback(.success(0, [true]))
                return
            }
            
            let contentLength = response.expectedContentLength
            guard contentLength != -1 else { // `-1` because no `NSURLResponseUnknownLength` in Swift
                callback(.success(nil, [false]))
                return
            }
            
            callback(.success(contentLength, [false]))
        }
        currentTask = task
        task.resume()
    }
    
    private func download(_ items: ArraySlice<(Item, Cached)>, _ callback: @escaping (Result) -> ()) {
        currentItemIndex = items.startIndex
        
        guard let first = items.first else {
            callback(.success)
            return
        }
        
        let (item, cached) = first
        download(item, cached) { result in
            switch result {
            case .cancel, .failure:
                callback(result)
            case .success:
                self.download(items[(items.startIndex + 1)..<items.endIndex], callback)
            }
        }
    }
    
    private func download(_ item: Item, _ cached: Cached, _ callback: @escaping (Result) -> ()) {
        guard !canceled else {
            callback(.cancel)
            return
        }
        
        guard !cached else {
            callback(.success)
            return
        }
        
        currentItem = item
        currentCallback = callback
        
        let request = NSMutableURLRequest(url: item.url)
        commonRequestHeaders?.forEach {
            request.setValue($0.1, forHTTPHeaderField: $0.0)
        }
        switch item.strategy ?? commonStrategy {
        case .always:
            break
        case .ifUpdated:
            if let ifModifiedSince = item.ifModifiedSince {
                request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
            }
        case .ifNotCached:
            callback(.success)
            return
        }
        
        let task = session.downloadTask(with: request as URLRequest)
        currentTask = task
        task.resume()
    }
    
    private func makeProgress(bytesDownloaded: Int64, totalBytesDownloadedForItem: Int64, totalBytesExpectedToDownloadForItem: Int64?) {
        if let _ = self.bytesDownloaded {
            self.bytesDownloaded! += bytesDownloaded
        } else {
            self.bytesDownloaded = bytesDownloaded
        }
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
        
        session.finishTasksAndInvalidate()
        session = nil
        // `self` is released by this if it is not retained outside
        // because the `delegate` which retains `self` is released.
    }
    
    public func cancel() {
        DispatchQueue.main.async {
            guard !self.canceled else { return }
            
            self.canceled = true
            self.currentTask?.cancel()
        }
    }
    
    public func progress(_ handler: @escaping (Int64, Int64?, Int, Int64, Int64?) -> ()) {
        DispatchQueue.main.async { [weak self] in
            if let zelf = self, let bytesDownloaded = zelf.bytesDownloaded {
                handler(bytesDownloaded, zelf.bytesExpectedToDownload, zelf.items.count, zelf.bytesDownloadedForItem, zelf.bytesExpectedToDownloadForItem)
            }
            guard let zelf = self, zelf.result == nil else {
                return
            }
            
            self?.progressHandlers.append(handler)
        }
    }
    
    public func completion(_ handler: @escaping (Result) -> ()) {
        DispatchQueue.main.async {
            if let result = self.result {
                handler(result)
                return
            }
            
            self.completionHandlers.append(handler)
        }
    }
    
    public enum Strategy {
        case always, ifUpdated, ifNotCached
    }
    
    public struct Item {
        public var url: URL
        public var destination: String
        public var strategy: Strategy?
        
        public init(url: URL, destination: String, strategy: Strategy? = nil) {
            self.url = url
            self.destination = destination
            self.strategy = strategy
        }
        
        internal var modificationDate: Date? {
            return (try? FileManager.default.attributesOfItem(atPath: destination))?[FileAttributeKey.modificationDate] as? Date
        }
        
        internal var ifModifiedSince: String? {
            return modificationDate.map { Downloader.dateFormatter.string(from: $0) }
        }
        
        internal var fileExists: Bool {
            return FileManager.default.fileExists(atPath: destination)
        }
    }
    
    public enum Result {
        case success
        case cancel
        case failure(Error)
    }
    
    public struct ResponseError: Error {
        let response: URLResponse
    }
    
    private enum ContentLengthResult {
        case success(Int64?, [Cached])
        case canceled
        case failure(Error)
    }
    
    private class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        let downloader: Downloader
        
        init(downloader: Downloader) {
            self.downloader = downloader
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let callback = downloader.currentCallback!

            if downloader.canceled {
                callback(.cancel)
                return
            }
            
            if let error = error {
                callback(.failure(error))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let item = downloader.currentItem!
            let callback = downloader.currentCallback!

            let response = (downloadTask.response as? HTTPURLResponse)!
            if response.statusCode == 304 {
                callback(.success)
                return
            }
            guard response.statusCode == 200 else {
                callback(.failure(ResponseError(response: response)))
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
                callback(.success)
            } catch let error {
                callback(.failure(error))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            downloader.bytesDownloadedForItem = totalBytesWritten
            downloader.bytesExpectedToDownloadForItem = totalBytesExpectedToWrite
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
