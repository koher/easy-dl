# EasyDL

_EasyDL_ makes it easy to **download multiple files** in Swift.

```swift
try await download([
    (from: url1, to: file1),
    (from: url2, to: file2),
]) { bytesDownloaded,bytesExpectedToDownload in
    print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
}

let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
```

## Cache policies

It is possible to choose cache policies for a `Downloader` and/or each `Item`.

```swift
enum CachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataIfUnmodifiedElseLoad
    case returnCacheDataElseLoad
}
```

```swift
let item1 = Downloader.Item(url: url1, destination: file1) // `.returnCacheDataIfUnmodifiedElseLoad` by default
let item2 = Downloader.Item(url: url2, destination: file2, cachePolicy: .returnCacheDataElseLoad)
let item3 = Downloader.Item(url: url3, destination: file3, cachePolicy: .returnCacheDataElseLoad)

try await download(items: [item1, item2, item3])
```

## Progress handling

Following three overloads of `progress` are available.

```swift
try await download(items: items) { (bytesDownloaded: Int, bytesExpectedToDownload: Int?) in
    print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
}
```

```swift
try await download(items: items) { (rate: Float?) in
    print("\(rate!) / 1.0")
}
```

```swift
try await download(items: items) { (
    bytesDownloaded: Int,
    bytesExpectedToDownload: Int?,
    currentItemIndex: Int,
    bytesDownloadedForCurrentItem: Int,
    bytesExpectedToDownloadForCurrentItem: Int?
) in
    print("\(currentItemIndex) / \(items.count)")
}
```

Also precise progress or non-precise progress can be designated.

```swift
try await download(items: items, expectsPreciseProgress: true) { ... }
```

Usually, a `download` gets sizes of the `Item`s by sending HEAD requests and summing up `Content-Length`s in the response headers before starting downloads. When `expectsPreciseProgress` is `false`, a `Downloader` omits those requests. Then `progress` for `Float?` calls a callback with pseudo progress, which is calculated on the assumption that all `Item`s has a same size. That is, the amout of the progress for each `Item` is `1.0 / Float(items.count)`.

## License

[The MIT License](LICENSE)
