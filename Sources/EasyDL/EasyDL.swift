import Foundation

internal typealias IsCached = Bool

public final class Downloader {
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
    
    private var session: Session
    private var zelf: Downloader? // To prevent releasing this instance during downloading

    private var currentItemIndex: Int = 0
    private var currentItem: Item! = nil
    private var currentCallback: ((Result) -> ())? = nil
    private var currentTask: URLSessionTask? = nil
    
    private var isCancelled: Bool = false
    
    public convenience init(
        items: [Item],
        needsPreciseProgress: Bool = true,
        commonStrategy: Strategy = .ifUpdated,
        commonRequestHeaders: [String: String]? = nil
    ) {
        self.init(session: FoundationURLSession(), items: items, needsPreciseProgress: needsPreciseProgress, commonStrategy: commonStrategy, commonRequestHeaders: commonRequestHeaders)
    }

    internal init(
        session: Session,
        items: [Item],
        needsPreciseProgress: Bool,
        commonStrategy: Strategy,
        commonRequestHeaders: [String: String]?
    ) {
        self.session = session
        self.items = items
        self.needsPreciseProgress = needsPreciseProgress
        self.commonStrategy = commonStrategy
        self.commonRequestHeaders = commonRequestHeaders
        
        zelf = self
        
        func download(_ isCached: [IsCached]) {
            assert(items.count == isCached.count) // Always true for `Downloader` without bugs
            self.download(ArraySlice(zip(items, isCached)), self.complete(with:))
        }

        if needsPreciseProgress {
            contentLength(of: items[0..<items.count]) { result in
                switch result {
                case .cancel:
                    self.complete(with: .cancel)
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
                let tail = items[(items.startIndex + 1)..<items.endIndex]
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
        commonRequestHeaders?.forEach {
            headerFields[$0.0] = $0.1
        }
        switch item.strategy ?? commonStrategy {
        case .always:
            break
        case .ifUpdated:
            modificationDate = item.modificationDate
        case .ifNotCached:
            callback(.success(0, [true]))
            return
        }
        let request = Session.Request(url: item.url, modificationDate: modificationDate, headerFields: headerFields)
        session.contentLengthWith(request, callback)
    }
    
    private func download(_ items: ArraySlice<(Item, IsCached)>, _ callback: @escaping (Result) -> ()) {
        currentItemIndex = items.startIndex
        
        guard let first = items.first else {
            callback(.success)
            return
        }
        
        let (item, isCached) = first
        download(item, isCached) { result in
            switch result {
            case .cancel, .failure:
                callback(result)
            case .success:
                self.download(items[(items.startIndex + 1)..<items.endIndex], callback)
            }
        }
    }
    
    private func download(_ item: Item, _ isCached: IsCached, _ callback: @escaping (Result) -> ()) {
        if isCancelled {
            callback(.cancel)
            return
        }
        
        if isCached {
            callback(.success)
            return
        }
        
        currentItem = item
        currentCallback = callback
        
        var modificationDate: Date?
        var headerFields: [String: String] = [:]
        commonRequestHeaders?.forEach {
            headerFields[$0.0] = $0.1
        }
        switch item.strategy ?? commonStrategy {
        case .always:
            break
        case .ifUpdated:
            modificationDate = item.modificationDate
        case .ifNotCached:
            callback(.success)
            return
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
                    callback(.success)
                } catch let error {
                    callback(.failure(error))
                }
            case .success(.none):
                callback(.success)
            case .cancel:
                callback(.cancel)
            case .failure(let error):
                callback(.failure(error))
            }
        })
    }
    
    private func makeProgress(bytesDownloaded: Int64, totalBytesDownloadedForItem: Int64, totalBytesExpectedToDownloadForItem: Int64?) {
        if let _ = self.bytesDownloaded {
            self.bytesDownloaded! += bytesDownloaded
        } else {
            self.bytesDownloaded = bytesDownloaded
        }
        progressHandlers.forEach {
            $0(
                self.bytesDownloaded,
                self.bytesExpectedToDownload,
                self.currentItemIndex,
                totalBytesDownloadedForItem,
                totalBytesExpectedToDownloadForItem
            )
        }
    }
    
    private func complete(with result: Result) {
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
            self.currentTask?.cancel()
        }
    }
    
    public func progress(
        _ handler: @escaping (
            _ bytesDownloaded: Int64,
            _ bytesExpectedToDownload: Int64?,
            _ itemIndex: Int,
            _ bytesDownloadedForItem: Int64,
            _ bytesExpectedToDownloadForItem: Int64?
        ) -> ()
    ) {
        DispatchQueue.main.async { [weak self] in
            if let self = self, let bytesDownloaded = self.bytesDownloaded {
                handler(
                    bytesDownloaded,
                    self.bytesExpectedToDownload,
                    self.items.count,
                    self.bytesDownloadedForItem,
                    self.bytesExpectedToDownloadForItem
                )
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
        public let response: URLResponse
    }
    
    internal enum ContentLengthResult {
        case success(Int64?, [IsCached])
        case cancel
        case failure(Error)
    }
}
