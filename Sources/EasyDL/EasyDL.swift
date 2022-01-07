import Foundation

internal typealias IsCached = Bool

public final class Downloader {
    public let items: [Item]
    public let expectsPreciseProgress: Bool
    public let cachePolicy: CachePolicy
    public let requestHeaders: [String: String]?
    
    private var progressHandlers: [(Progress) -> Void] = []
    private var completionHandlers: [(Result<Void, Error>) -> ()] = []

    private var bytesDownloaded: Int! = nil
    private var bytesExpectedToDownload: Int? = nil
    private var bytesDownloadedForItem: Int! = nil
    private var bytesExpectedToDownloadForItem: Int? = nil
    private var result: Result<Void, Error>? = nil
    
    private let urlSession: URLSession
    private var zelf: Downloader? // To prevent releasing this instance during downloading

    private var currentItemIndex: Int = 0
    private var currentTask: URLSessionTask? = nil
    private var currentResultHandler: ((Result<(location: URL, modificationDate: Date?)?, Error>) -> Void)? = nil

    private var isCancelled: Bool = false
    
    public init(
        items: [Item],
        expectsPreciseProgress: Bool = true,
        cachePolicy: CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
        requestHeaders: [String: String]? = nil
    ) {
        let urlSessionDelegate = URLSessionDelegateObject()
        self.urlSession = URLSession(configuration: .default, delegate: urlSessionDelegate, delegateQueue: .main)
        self.items = items
        self.expectsPreciseProgress = expectsPreciseProgress
        self.cachePolicy = cachePolicy
        self.requestHeaders = requestHeaders
        
        urlSessionDelegate.object = self

        zelf = self
        
        @Sendable func download(_ isCached: [IsCached]) {
            assert(items.count == isCached.count) // Always true for `Downloader` without bugs
            self.download(ArraySlice(zip(items, isCached)), self.complete(with:))
        }

        if expectsPreciseProgress {
            Task {
                do {
                    let (length, isCached) = try await contentLength(of: items[...])
                    self.bytesExpectedToDownload = length
                    download(isCached)
                } catch {
                    self.complete(with: .failure(error))
                }
            }
        } else {
            download([IsCached](repeating: false, count: items.count))
        }
    }
    
    private func contentLength(of items: ArraySlice<Item>) async throws -> (length: Int?, isCached: [IsCached]) {
        guard let first = items.first else {
            return (length: 0, isCached: [])
        }
        
        let (headLength, headCached) = try await contentLength(of: first)
        
        let tail = items[(items.startIndex + 1)...]
        guard let headLength = headLength else {
            return (length: nil, isCached: headCached + [IsCached](repeating: false, count: items.count - 1))
        }
        
        let (tailLength, tailCached) = try await self.contentLength(of: tail)
        guard let tailLength = tailLength else {
            return (length: nil, isCached: headCached + tailCached)
        }
        
        return (headLength + tailLength, headCached + tailCached)
    }
    
    private func contentLength(of item: Item) async throws -> (length: Int?, isCached: [IsCached]) {
        if isCancelled {
            throw CancellationError()
        }
        
        var modificationDate: Date?
        var headerFields: [String: String] = [:]
        requestHeaders?.forEach {
            headerFields[$0.0] = $0.1
        }
        switch item.cachePolicy ?? cachePolicy {
        case .reloadIgnoringLocalCacheData:
            break
        case .returnCacheDataIfUnmodifiedElseLoad:
            modificationDate = item.modificationDate
        case .returnCacheDataElseLoad:
            if item.fileExists {
                return (length: 0, isCached: [true])
            }
        }
        
        var urlRequest = URLRequest(url: item.url)
        urlRequest.httpMethod = "HEAD"
        urlRequest.setHeaderFields(headerFields, with: modificationDate)
        return try await withCheckedThrowingContinuation { continuation in
            if isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            let task = urlSession.dataTask(with: urlRequest) { _, urlResponse, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let urlResponse = urlResponse as? HTTPURLResponse else {
                    continuation.resume(returning: (length: nil, isCached: [false]))
                    return
                }
                
                if urlResponse.statusCode == 304 {
                    continuation.resume(returning: (length: 0, isCached: [true]))
                    return
                }
                
                let contentLength = urlResponse.expectedContentLength
                if contentLength == -1 { // `-1` because no `NSURLResponseUnknownLength` in Swift
                    continuation.resume(returning: (length: nil, isCached: [false]))
                    return
                }
                
                continuation.resume(returning: (length: Int(contentLength), isCached: [false]))
            }
            self.currentTask = task
            task.resume()
        }
    }
    
    private func download(_ items: ArraySlice<(Item, IsCached)>, _ callback: @escaping (Result<Void, Error>) -> ()) {
        currentItemIndex = items.startIndex
        
        guard let first = items.first else {
            callback(.success(()))
            return
        }
        
        let (item, isCached) = first
        download(item, isCached) { result in
            switch result {
            case .failure:
                callback(result)
            case .success:
                self.download(items[(items.startIndex + 1)...], callback)
            }
        }
    }
    
    private func download(_ item: Item, _ isCached: IsCached, _ callback: @escaping (Result<Void, Error>) -> ()) {
        if isCancelled {
            callback(.failure(CancellationError()))
            return
        }
        
        if isCached {
            callback(.success(()))
            return
        }
        
        var modificationDate: Date?
        var headerFields: [String: String] = [:]
        requestHeaders?.forEach {
            headerFields[$0.0] = $0.1
        }
        switch item.cachePolicy ?? cachePolicy {
        case .reloadIgnoringLocalCacheData:
            break
        case .returnCacheDataIfUnmodifiedElseLoad:
            modificationDate = item.modificationDate
        case .returnCacheDataElseLoad:
            break
        }
        
        var urlRequest = URLRequest(url: item.url)
        urlRequest.setHeaderFields(headerFields, with: modificationDate)

        currentResultHandler = { result in
            switch result {
            case .success((location: let location, modificationDate: let modificationDate)?):
                let fileManager = FileManager.default
                try? fileManager.removeItem(atPath: item.destination) // OK though it fails if the file does not exists
                do {
                    try fileManager.moveItem(at: location, to: URL(fileURLWithPath: item.destination))
                    if let modificationDate = modificationDate {
                        try fileManager.setAttributes([.modificationDate: modificationDate], ofItemAtPath: item.destination)
                    }
                    callback(.success(()))
                } catch let error {
                    callback(.failure(error))
                }
            case .success(.none):
                callback(.success(()))
            case .failure(let error):
                callback(.failure(error))
            }
        }
        
        let task = urlSession.downloadTask(with: urlRequest)
        currentTask = task
        task.resume()
    }
    
    private func makeProgress(bytesDownloaded: Int, totalBytesDownloadedForItem: Int, totalBytesExpectedToDownloadForItem: Int?) {
        if let _ = self.bytesDownloaded {
            self.bytesDownloaded! += bytesDownloaded
        } else {
            self.bytesDownloaded = bytesDownloaded
        }
        progressHandlers.forEach {
            $0(Progress(
                bytesDownloaded: self.bytesDownloaded,
                bytesExpectedToDownload: self.bytesExpectedToDownload,
                itemIndex: self.currentItemIndex,
                numberOfItems: self.items.count,
                bytesDownloadedForItem: totalBytesDownloadedForItem,
                bytesExpectedToDownloadForItem: totalBytesExpectedToDownloadForItem
            ))
        }
    }
    
    private func complete(with result: Result<Void, Error>) {
        guard self.result == nil else { return }
        
        completionHandlers.forEach {
            $0(result)
        }
        
        self.result = result
        
        progressHandlers.removeAll()
        completionHandlers.removeAll()
        
        zelf = nil
    }
    
    public func cancel() {
        DispatchQueue.main.async {
            if self.isCancelled { return }
            
            self.isCancelled = true
            self.complete(with: .failure(CancellationError()))
            self.currentTask?.cancel()
        }
    }
    
    public func progress(_ handler: @escaping (Progress) -> Void) {
        DispatchQueue.main.async {
            if let bytesDownloaded = self.bytesDownloaded {
                handler(Progress(
                    bytesDownloaded: bytesDownloaded,
                    bytesExpectedToDownload: self.bytesExpectedToDownload,
                    itemIndex: self.items.count,
                    numberOfItems: self.items.count,
                    bytesDownloadedForItem: self.bytesDownloadedForItem,
                    bytesExpectedToDownloadForItem: self.bytesExpectedToDownloadForItem
                ))
            }
            guard self.result == nil else {
                return
            }
            
            self.progressHandlers.append(handler)
        }

    }
    
    public func progress(
        _ handler: @escaping (
            _ bytesDownloaded: Int,
            _ bytesExpectedToDownload: Int?,
            _ itemIndex: Int,
            _ bytesDownloadedForItem: Int,
            _ bytesExpectedToDownloadForItem: Int?
        ) -> ()
    ) {
        progress { progress in
            handler(
                progress.bytesDownloaded,
                progress.bytesExpectedToDownload,
                progress.itemIndex,
                progress.bytesDownloadedForItem,
                progress.bytesExpectedToDownloadForItem
            )
        }
    }
    
    public func completion(_ handler: @escaping (Result<Void, Error>) -> ()) {
        DispatchQueue.main.async {
            if let result = self.result {
                handler(result)
                return
            }
            
            self.completionHandlers.append(handler)
        }
    }
    
    public struct Progress {
        public let bytesDownloaded: Int
        public let bytesExpectedToDownload: Int?
        public let itemIndex: Int
        public let numberOfItems: Int
        public let bytesDownloadedForItem: Int
        public let bytesExpectedToDownloadForItem: Int?

        internal init(bytesDownloaded: Int, bytesExpectedToDownload: Int?, itemIndex: Int, numberOfItems: Int, bytesDownloadedForItem: Int, bytesExpectedToDownloadForItem: Int?) {
            self.bytesDownloaded = bytesDownloaded
            self.bytesExpectedToDownload = bytesExpectedToDownload
            self.itemIndex = itemIndex
            self.numberOfItems = numberOfItems
            self.bytesDownloadedForItem = bytesDownloadedForItem
            self.bytesExpectedToDownloadForItem = bytesExpectedToDownloadForItem
        }
        
        public var rate: Float {
            if let exptected = bytesExpectedToDownload {
                return Float(bytesDownloaded) / Float(exptected)
            } else if let exptected = bytesExpectedToDownloadForItem {
                return (Float(itemIndex) + Float(Double(bytesDownloadedForItem) / Double(exptected))) / Float(numberOfItems)
            } else {
                return Float(itemIndex) / Float(numberOfItems)
            }
        }
    }
    
    public enum CachePolicy {
        case reloadIgnoringLocalCacheData
        case returnCacheDataIfUnmodifiedElseLoad
        case returnCacheDataElseLoad
    }
    
    public struct Item {
        public var url: URL
        public var destination: String
        public var cachePolicy: CachePolicy?
        
        public init(url: URL, destination: String, cachePolicy: CachePolicy? = nil) {
            self.url = url
            self.destination = destination
            self.cachePolicy = cachePolicy
        }
        
        internal var modificationDate: Date? {
            return (try? FileManager.default.attributesOfItem(atPath: destination))?[FileAttributeKey.modificationDate] as? Date
        }
        
        internal var fileExists: Bool {
            return FileManager.default.fileExists(atPath: destination)
        }
    }
    
    public struct ResponseError: Error {
        public let response: URLResponse
    }
}

extension Downloader {
    private final class URLSessionDelegateObject: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        var object: Downloader!
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let handler = object.currentResultHandler!

            if object.isCancelled {
                handler(.failure(CancellationError()))
                return
            }
            
            if let error = error {
                handler(.failure(error))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let handler = object.currentResultHandler!

            let response = (downloadTask.response as? HTTPURLResponse)!
            if response.statusCode == 304 {
                handler(.success(nil))
                return
            }
            guard response.statusCode == 200 else {
                handler(.failure(Downloader.ResponseError(response: response)))
                return
            }
            
            if let lastModified = response.allHeaderFields["Last-Modified"] as? String,
                let modificationDate = Downloader.dateFormatter.date(from: lastModified) {
                handler(.success((location: location, modificationDate: modificationDate)))
            } else {
                handler(.success((location: location, modificationDate: nil)))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let bytesDownloaded = Int(bytesWritten)
            let totalBytesDownloaded = Int(totalBytesWritten)
            let totalBytesExpectedToDownload: Int? = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
            ? nil : Int(totalBytesExpectedToWrite)
            object.bytesDownloadedForItem = totalBytesDownloaded
            object.bytesExpectedToDownloadForItem = totalBytesExpectedToDownload
            object.makeProgress(
                bytesDownloaded: bytesDownloaded,
                totalBytesDownloadedForItem: totalBytesDownloaded,
                totalBytesExpectedToDownloadForItem: totalBytesExpectedToDownload
            )
        }
    }
}

private extension Downloader {
    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(abbreviation: "GMT")!
        return formatter
    }
}

private extension URLRequest {
    mutating func setHeaderFields(_ headerFields: [String: String], with modificationDate: Date?) {
        headerFields.forEach { setValue($0.1, forHTTPHeaderField: $0.0) }
        if let modificationDate = modificationDate {
            let ifModifiedSince = Downloader.dateFormatter.string(from: modificationDate)
            setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
    }
}
