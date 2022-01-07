import XCTest
import EasyDL

@MainActor
final class DownloadTests: XCTestCase {
    override class func setUp() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: testDirectoryURL)
        try? fileManager.createDirectory(at: testDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override class func tearDown() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: testDirectoryURL)
    }
    
    func testSuccess() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        
        try await download(items: [(url1, file1), (url2, file2)])
        
        let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
        XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
        
        let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
        XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
    }
    
    func testFailure() async throws {
        let url1 = URL(string: "https://koherent.org/pi/not-found.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path

        do {
            try await download(items: [(url1, file1), (url2, file2)])
            XCTFail()
        } catch let error as Downloader.ResponseError {
            XCTAssertEqual((error.response as! HTTPURLResponse).statusCode, 404)
        }
    }
    
    func testCancel() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi100000.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi1000000.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi100000.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi1000000.txt").path

        let task = Task {
            do {
                try await download(items: [(url1, file1), (url2, file2)], requestHeaders: ["Accept-Encoding": "identity"], progressHandler: { bytesDownloaded, bytesExpectedToDownload in
                    print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
                })
                XCTFail()
            } catch is CancellationError {
                // OK
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()
        _ = try await task.value
    }
}
