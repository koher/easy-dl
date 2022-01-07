import Foundation

extension Downloader {
    public convenience init(
        items: [(URL, String)],
        expectsPreciseProgress: Bool = true,
        cachePolicy: CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
        requestHeaders: [String: String]? = nil
    ) {
        self.init(
            items: items.map { Item(url: $0.0, destination: $0.1) },
            expectsPreciseProgress: expectsPreciseProgress,
            cachePolicy: cachePolicy,
            requestHeaders: requestHeaders
        )
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
    
    public func progress(
        _ handler: @escaping (
            _ bytesDownloaded: Int,
            _ bytesExpectedToDownload: Int?
        ) -> ()
    ) {
        progress { done, whole, _, _, _ in
            handler(done, whole)
        }
    }
    
    public func progressRate(_ handler: @escaping (Float) -> ()) {
        progress { progress in
            handler(progress.rate)
        }
    }
}
