import XCTest
import EasyDL

final class DownloadTests: XCTestCase {
    private static var directoryURL: URL { URL(fileURLWithPath: dir) }
    
    override class func setUp() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: directoryURL)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override class func tearDown() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: directoryURL)
    }
    
    func testSuccess() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = Self.directoryURL.appendingPathComponent("pi10.txt").path
        let file2 = Self.directoryURL.appendingPathComponent("pi100.txt").path
        
        try await download(items: [(url1, file1), (url2, file2)])
        
        let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
        XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
        
        let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
        XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
    }
    
    func testFailure() async throws {
        let url1 = URL(string: "https://koherent.org/pi/not-found.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = Self.directoryURL.appendingPathComponent("pi10.txt").path
        let file2 = Self.directoryURL.appendingPathComponent("pi100.txt").path

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
        let file1 = Self.directoryURL.appendingPathComponent("pi100000.txt").path
        let file2 = Self.directoryURL.appendingPathComponent("pi1000000.txt").path
        
        do {
            async let x: Void = download(items: [(url1, file1), (url2, file2)], requestHeaders: ["Accept-Encoding": "identity"], progressHandler: { bytesDownloaded, bytesExpectedToDownload in
                print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
            })
            
            withUnsafeCurrentTask { task in
                _ = Task.detached {
                    print(Thread.current, Thread.main, Thread.isMainThread)
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    task!.cancel()
                }
            }
            
            try await x
            
            XCTFail()
        } catch is CancellationError {
            // OK
        }
    }
}
