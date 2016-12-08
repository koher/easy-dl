import XCTest
@testable import SwiftDL

import Foundation

class SwiftDLTests: XCTestCase {
    func testExample() {
        let dir: String = Bundle(for: type(of: self)).resourcePath!
        
        let url1 = URL(string: "http://koherent.org/pi/pi10.txt")!
        let url2 = URL(string: "http://koherent.org/pi/pi100.txt")!
        let file1 = (dir as NSString).appendingPathComponent("pi10.txt")
        let file2 = (dir as NSString).appendingPathComponent("pi100.txt")
        
        let downloader = Downloader(items: [(url1, file1), (url2, file2)], commonRequestHeaders: ["Accept-Encoding": "identity"])
        
        let expectation = self.expectation(description: "")
        
        downloader.handleProgress { bytesDownloaded, bytesExpectedToDownload in
            print("\(bytesDownloaded) / \(bytesExpectedToDownload)")
        }
        
        downloader.handleCompletion { result in
            switch result {
            case .success:
                let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
                XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
                
                let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
                XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
                
                break
            case let .failure(error):
                XCTFail("\(error)")
                break
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    func testProgress() {
        
    }
    
    func testCompletion() {
        
    }

    static var allTests : [(String, (SwiftDLTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
            ("testProgress", testProgress),
            ("testCompletion", testCompletion),
        ]
    }
}
