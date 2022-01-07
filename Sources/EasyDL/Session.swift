import Foundation

internal final class Session {
    struct Request {
        let url: URL
        var modificationDate: Date?
        var headerFields: [String: String]
    }
    
    struct Progress {
        var bytesDownloaded: Int
        var totalBytesDownloaded: Int
        var totalBytesExpectedToDownload: Int?
    }
    
    enum Result {
        case success((location: URL, modificationDate: Date?)?)
        case cancel
        case failure(Error)
    }
    
    private var session: URLSession! = nil
    private var currentTask: URLSessionTask? = nil
    
    private var currentProgressHandler: ((Progress) -> Void)? = nil
    private var currentResultHandler: ((Result) -> Void)? = nil
    
    private var isCancelled = false
    
    init() {
        session = URLSession(configuration: .default, delegate: Delegate(for: self), delegateQueue: .main)
    }
    
    private static func setHeaderFields(of urlRequest: inout URLRequest, from request: Request) {
        request.headerFields.forEach { urlRequest.setValue($0.1, forHTTPHeaderField: $0.0) }
        if let modificationDate = request.modificationDate {
            let ifModifiedSince = Self.dateFormatter.string(from: modificationDate)
            urlRequest.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
    }
    
    func contentLengthWith(_ request: Request, _ handler: @escaping (Downloader.ContentLengthResult) -> Void) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "HEAD"
        Self.setHeaderFields(of: &urlRequest, from: request)
        let task = session.dataTask(with: urlRequest) { _, urlResponse, error in
            if let error = error {
                handler(.failure(error))
                return
            }
            
            guard let urlResponse = urlResponse as? HTTPURLResponse else {
                handler(.success(nil, [false]))
                return
            }
            
            if urlResponse.statusCode == 304 {
                handler(.success(0, [true]))
                return
            }
            
            let contentLength = urlResponse.expectedContentLength
            if contentLength == -1 { // `-1` because no `NSURLResponseUnknownLength` in Swift
                handler(.success(nil, [false]))
                return
            }
            
            handler(.success(Int(contentLength), [false]))
        }
        self.currentTask = task
        task.resume()
    }
    
    func downloadWith(
        _ request: Request,
        progressHandler: @escaping (Progress) -> Void,
        resultHandler: @escaping (Result) -> Void
    ) {
        currentProgressHandler = progressHandler
        currentResultHandler = resultHandler
        
        var urlRequest = URLRequest(url: request.url)
        Self.setHeaderFields(of: &urlRequest, from: request)

        let task = session.downloadTask(with: urlRequest)
        currentTask = task
        task.resume()
    }

    func cancel() {
        guard let task = currentTask else { return }
        isCancelled = true
        task.cancel()
    }
    
    func complete() {
        session.finishTasksAndInvalidate()
        session = nil
        // `self` is released by this if it is not retained outside
        // because the `delegate` which retains `self` is released.
    }

    class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        private let object: Session
        
        init(for object: Session) {
            self.object = object
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let handler = object.currentResultHandler!

            if object.isCancelled {
                handler(.cancel)
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
                let modificationDate = Session.dateFormatter.date(from: lastModified) {
                handler(.success((location: location, modificationDate: modificationDate)))
            } else {
                handler(.success((location: location, modificationDate: nil)))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let handler = object.currentProgressHandler!
            
            let progress = Progress(
                bytesDownloaded: Int(bytesWritten),
                totalBytesDownloaded: Int(totalBytesWritten),
                totalBytesExpectedToDownload: totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
                    ? nil : Int(totalBytesExpectedToWrite)
            )
            handler(progress)
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
