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
    
    private let session: Session
    private var zelf: Downloader? // To prevent releasing this instance during downloading

    private var currentItemIndex: Int = 0
    private var currentItem: Item! = nil
    private var currentCallback: ((Result<Void, Error>) -> ())? = nil
    
    private var isCancelled: Bool = false
    
    public convenience init(
        items: [Item],
        expectsPreciseProgress: Bool = true,
        cachePolicy: CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
        requestHeaders: [String: String]? = nil
    ) {
        self.init(session: Session(), items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    }

    internal init(
        session: Session,
        items: [Item],
        expectsPreciseProgress: Bool,
        cachePolicy: CachePolicy,
        requestHeaders: [String: String]?
    ) {
        self.session = session
        self.items = items
        self.expectsPreciseProgress = expectsPreciseProgress
        self.cachePolicy = cachePolicy
        self.requestHeaders = requestHeaders
        
        zelf = self
        
        func download(_ isCached: [IsCached]) {
            assert(items.count == isCached.count) // Always true for `Downloader` without bugs
            self.download(ArraySlice(zip(items, isCached)), self.complete(with:))
        }

        if expectsPreciseProgress {
            contentLength(of: items[...]) { result in
                switch result {
                case .cancel:
                    self.complete(with: .failure(CancellationError()))
                case let .failure(error):
                    self.complete(with: .failure(error))
                case let .success(length, isCached):
                    self.bytesExpectedToDownload = length
                    download(isCached)
                }
            }
        } else {
            download([IsCached](repeating: false, count: items.count))
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
            case .cancel, .failure:
                callback(result)
            case let .success(headLength, headCached):
                let tail = items[(items.startIndex + 1)...]
                guard let headLength = headLength else {
                    callback(.success(nil, headCached + [IsCached](repeating: false, count: items.count - 1)))
                    break
                }
                
                self.contentLength(of: tail) { result in
                    switch result {
                    case .cancel, .failure:
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
        if isCancelled {
            callback(.cancel)
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
        case .returnCacheDataElseLoad
:
            if item.fileExists {
                callback(.success(0, [true]))
                return
            }
        }
        let request = Session.Request(url: item.url, modificationDate: modificationDate, headerFields: headerFields)
        session.contentLengthWith(request, callback)
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
        
        currentItem = item
        currentCallback = callback
        
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
        case .returnCacheDataElseLoad
:
            break
        }

        let request = Session.Request(url: item.url, modificationDate: modificationDate, headerFields: headerFields)
        session.downloadWith(request, progressHandler: { [weak self] progress in
            guard let self = self else { return }
            
            self.bytesDownloadedForItem = progress.totalBytesDownloaded
            self.bytesExpectedToDownloadForItem = progress.totalBytesExpectedToDownload
            self.makeProgress(
                bytesDownloaded: progress.bytesDownloaded,
                totalBytesDownloadedForItem: progress.totalBytesDownloaded,
                totalBytesExpectedToDownloadForItem: progress.totalBytesExpectedToDownload
            )
        }, resultHandler: { result in
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
            case .cancel:
                callback(.failure(CancellationError()))
            case .failure(let error):
                callback(.failure(error))
            }
        })
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
        
        session.complete()
        zelf = nil
    }
    
    public func cancel() {
        DispatchQueue.main.async {
            if self.isCancelled { return }
            
            self.isCancelled = true
            self.complete(with: .failure(CancellationError()))
            self.session.cancel()
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
    
    internal enum ContentLengthResult {
        case success(Int?, [IsCached])
        case cancel
        case failure(Error)
    }
}
