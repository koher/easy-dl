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
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:]
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:]
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (Downloader.Progress) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (Downloader.Progress) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?,
        _ itemIndex: Int,
        _ bytesDownloadedForItem: Int,
        _ bytesExpectedToDownloadForItem: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?,
        _ itemIndex: Int,
        _ bytesDownloadedForItem: Int,
        _ bytesExpectedToDownloadForItem: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (
        _ bytesDownloaded: Int,
        _ bytesExpectedToDownload: Int?
    ) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progress(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    items: [Downloader.Item],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (Float) -> Void
) async throws {
    let downloader = Downloader(items: items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progressRate(progressHandler)
    try await download(with: downloader)
}

@MainActor
public func download(
    _ items: [(from: URL, to: String)],
    expectsPreciseProgress: Bool = true,
    cachePolicy: Downloader.CachePolicy = .returnCacheDataIfUnmodifiedElseLoad,
    timeoutInterval: TimeInterval = 60.0,
    requestHeaders: [String: String] = [:],
    progressHandler: @escaping (Float) -> Void
) async throws {
    let downloader = Downloader(items, expectsPreciseProgress: expectsPreciseProgress, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval, requestHeaders: requestHeaders)
    downloader.progressRate(progressHandler)
    try await download(with: downloader)
}
