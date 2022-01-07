import XCTest
import EasyDL
import Foundation

internal let testDirectoryURL: URL = .init(fileURLWithPath:  #file.deletingLastPathComponent.deletingLastPathComponent.deletingLastPathComponent.appendingPathComponent("TemporaryTestDirectory"))

@MainActor
final class EasyDLTests: XCTestCase {
    override func setUp() async throws {
        let fileManager: FileManager = .default
        if fileManager.fileExists(atPath: testDirectoryURL.path) {
            try fileManager.removeItem(at: testDirectoryURL)
        }
        try fileManager.createDirectory(at: testDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() async throws {
        let fileManager: FileManager = .default
        if fileManager.fileExists(atPath: testDirectoryURL.path) {
            try fileManager.removeItem(at: testDirectoryURL)
        }
    }
    
    func testExample() async throws {
        /**/ let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        /**/ let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        /**/ let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        /**/ let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        
        /**/ var progressSet: Set<String> = []
        try await download([
            (from: url1, to: file1),
            (from: url2, to: file2),
        ]/**/, requestHeaders: ["Accept-Encoding": "identity"]/**/) { bytesDownloaded, bytesExpectedToDownload in
            print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
            /**/ progressSet.insert("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
        }
        
        let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
        /**/ XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
        
        let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
        /**/ XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
        
        /**/ XCTAssertTrue(progressSet.contains("11 / 112"))
        /**/ XCTAssertTrue(progressSet.contains("112 / 112"))
    }
    
    func testCachePoliciesExample() async throws {
        /**/ let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        /**/ let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        /**/ let url3 = URL(string: "https://koherent.org/pi/pi1000.txt")!
        /**/ let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        /**/ let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        /**/ let file3 = testDirectoryURL.appendingPathComponent("pi1000.txt").path
        
        let item1 = Downloader.Item(url: url1, destination: file1) // `.returnCacheDataIfUnmodifiedElseLoad` by default
        let item2 = Downloader.Item(url: url2, destination: file2, cachePolicy: .returnCacheDataElseLoad)
        let item3 = Downloader.Item(url: url3, destination: file3, cachePolicy: .returnCacheDataElseLoad)

        try await download(items: [item1, item2, item3])
    }
    
    func testProgressExample() async throws {
        /**/ let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        /**/ let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        /**/ let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        /**/ let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path

        /**/ let item1 = Downloader.Item(url: url1, destination: file1)
        /**/ let item2 = Downloader.Item(url: url2, destination: file2)
        
        /**/ let items = [item1, item2]
        
        try await download(items: items) { (bytesDownloaded: Int, bytesExpectedToDownload: Int?) in
            print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
        }
        
        try await download(items: items) { (rate: Float?) in
            print("\(rate!) / 1.0")
        }
        
        try await download(items: items) { (
            bytesDownloaded: Int,
            bytesExpectedToDownload: Int?,
            currentItemIndex: Int,
            bytesDownloadedForCurrentItem: Int,
            bytesExpectedToDownloadForCurrentItem: Int?
        ) in
            print("\(currentItemIndex) / \(items.count)")
        }
        
        try await download(items: items, expectsPreciseProgress: true) { (rate: Float?) in
            print("\(rate!) / 1.0")
        }
    }
}
