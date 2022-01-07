import Foundation

@MainActor
private func download(with downloader: Downloader) async throws {
    return try await withTaskCancellationHandler(operation: {
        try await downloader.completion()
    }, onCancel: {
        Task { @MainActor in
            downloader.cancel()
        }
    })
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (Downloader.Progress) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (Downloader.Progress) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?,
        _ itemIndex: Int,
        _ bytesDownloadedForItem: Int,
        _ bytesExpectedToDownloadForItem: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?,
        _ itemIndex: Int,
        _ bytesDownloadedForItem: Int,
        _ bytesExpectedToDownloadForItem: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (Float) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progressRate(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    requestHeaders: [String: String]? = nil,
    progressHandler: @escaping (Float) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, requestHeaders: requestHeaders)
    downloader.progressRate(progressHandler)
    try await download(with: downloader)
}
