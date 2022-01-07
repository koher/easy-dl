import XCTest
import EasyDL
import Foundation

internal let testDirectoryURL: URL = .init(fileURLWithPath:  #file.deletingLastPathComponent.deletingLastPathComponent.appendingPathComponent("TemporaryTestDirectory"))

@MainActor
final class EasyDLTests: XCTestCase {
    override class func setUp() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: testDirectoryURL)
        try? fileManager.createDirectory(at: testDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override class func tearDown() {
        let fileManager: FileManager = .default
        try? fileManager.removeItem(at: testDirectoryURL)
    }
    
    func testExample() {
        /**/ let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        /**/ let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        /**/ let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        /**/ let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        
        let downloader = Downloader(items: [(url1, file1), (url2, file2)]/**/, requestHeaders: ["Accept-Encoding": "identity"]/**/)
        
        /**/ let expectation = self.expectation(description: "")
        
        /**/ var progressSet: Set<String> = []
        downloader.progress { bytesDownloaded, bytesExpectedToDownload in
            print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
            /**/ progressSet.insert("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
        }
        
        downloader.completion { result in
            switch result {
            case .success:
                let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
                /**/ XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
                
                let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
                /**/ XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
            case let .failure(error):
                /**/ XCTFail("\(error)")
            }
            /**/ expectation.fulfill()
        }
        
        /**/ waitForExpectations(timeout: 20.0, handler: nil)
        
        /**/ XCTAssertTrue(progressSet.contains("11 / 112"))
        /**/ XCTAssertTrue(progressSet.contains("112 / 112"))
    }
}
