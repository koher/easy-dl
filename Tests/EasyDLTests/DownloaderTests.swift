import XCTest
#if DEBUG
@testable import EasyDL
#else
import EasyDL
#endif

import Foundation

@MainActor
final class DownloaderTests: XCTestCase {
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
    
    func testProgress() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        
        let downloader = Downloader([(from: url1, to: file1), (from: url2, to: file2)], expectsPreciseProgress: false)
        
        var progressSet: Set<String> = []
        downloader.progressRate { (rate: Float?) in
            print("\(rate!) / 1.0")
            progressSet.insert("\(rate!) / 1.0")
        }
        
        try await downloader.completion()

        let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
        XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
        
        let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
        XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")

        XCTAssertTrue(progressSet.contains("0.5 / 1.0"))
        XCTAssertTrue(progressSet.contains("1.0 / 1.0"))
    }
    
    func testCache() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi10.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let url3 = URL(string: "https://koherent.org/pi/pi1000.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        let file3 = testDirectoryURL.appendingPathComponent("pi1000.txt").path
        
        let range: Range<Int>
        #if DEBUG
        range = 0 ..< 6
        #else
        range = 0 ..< 5
        #endif
        for count in range {
            let downloader: Downloader
            switch count {
            case 0:
                typealias Item = Downloader.Item
                let item1 = Item(url: url1, destination: file1)
                let item2 = Item(url: url2, destination: file2, cachePolicy: .returnCacheDataElseLoad) // tests downloading without cache with `.preferCache`
                downloader = Downloader(items: [item1, item2], requestHeaders: ["Accept-Encoding": "identity"])
            case 1:
                downloader = Downloader([(from: url1, to: file1), (from: url2, to: file2)], requestHeaders: ["Accept-Encoding": "identity"])
            case 2:
                downloader = Downloader([(from: url2, to: file2), (from: url3, to: file3)], requestHeaders: ["Accept-Encoding": "identity"])
            case 3:
                downloader = Downloader([(from: url1, to: file1), (from: url2, to: file2)], cachePolicy: .reloadIgnoringLocalCacheData, requestHeaders: ["Accept-Encoding": "identity"])
            case 4:
                typealias Item = Downloader.Item
                let item1 = Item(url: url1, destination: file1)
                let item2 = Item(url: url2, destination: file2, cachePolicy: .reloadIgnoringLocalCacheData)
                downloader = Downloader(items: [item1, item2], requestHeaders: ["Accept-Encoding": "identity"])
            #if DEBUG
            case 5:
                typealias Item = Downloader.Item
                let item1 = Item(url: url1, destination: file1)
                let item3 = Item(url: url3, destination: file3, cachePolicy: .returnCacheDataElseLoad)
                let fileManager = FileManager.default
                try! fileManager.setAttributes([.modificationDate: item1.modificationDate! - 1], ofItemAtPath: item1.destination)
                try! fileManager.setAttributes([.modificationDate: item3.modificationDate! - 1], ofItemAtPath: item3.destination)
                downloader = Downloader(items: [item1, item3], requestHeaders: ["Accept-Encoding": "identity"])
            #endif
            default:
                fatalError("Never reaches here.")
            }
            
            var progressSet: Set<String> = []
            downloader.progress { bytesDownloaded, bytesExpectedToDownload in
                print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
                progressSet.insert("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
            }
            
            try await downloader.completion()

            let data1 = try! Data(contentsOf: URL(fileURLWithPath: file1))
            XCTAssertEqual(String(bytes: data1, encoding: .utf8), "3.141592653")
            
            let data2 = try! Data(contentsOf: URL(fileURLWithPath: file2))
            XCTAssertEqual(String(bytes: data2, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067")
            
            if count >= 2 {
                let data3 = try! Data(contentsOf: URL(fileURLWithPath: file3))
                XCTAssertEqual(String(bytes: data3, encoding: .utf8), "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067982148086513282306647093844609550582231725359408128481117450284102701938521105559644622948954930381964428810975665933446128475648233786783165271201909145648566923460348610454326648213393607260249141273724587006606315588174881520920962829254091715364367892590360011330530548820466521384146951941511609433057270365759591953092186117381932611793105118548074462379962749567351885752724891227938183011949129833673362440656643086021394946395224737190702179860943702770539217176293176752384674818467669405132000568127145263560827785771342757789609173637178721468440901224953430146549585371050792279689258923542019956112129021960864034418159813629774771309960518707211349999998372978049951059731732816096318595024459455346908302642522308253344685035261931188171010003137838752886587533208381420617177669147303598253490428755468731159562863882353787593751957781857780532171226806613001927876611195909216420198")
            }

            switch count {
            case 0:
                XCTAssertTrue(progressSet.contains("11 / 112"))
                XCTAssertTrue(progressSet.contains("112 / 112"))
            case 1:
                XCTAssertTrue(progressSet.isEmpty)
            case 2:
                XCTAssertTrue(progressSet.contains("1001 / 1001"))
            case 3:
                XCTAssertTrue(progressSet.contains("11 / 112"))
                XCTAssertTrue(progressSet.contains("112 / 112"))
            case 4:
                XCTAssertTrue(progressSet.contains("101 / 101"))
            case 5:
                XCTAssertTrue(progressSet.contains("11 / 11"))
            default:
                fatalError("Never reaches here.")
            }
        }
    }
    
    func testCancel() async throws {
        let url1 = URL(string: "https://koherent.org/pi/pi100000.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi1000000.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi100000.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi1000000.txt").path
        
        let downloader = Downloader([(from: url1, to: file1), (from: url2, to: file2)], requestHeaders: ["Accept-Encoding": "identity"])
        
        downloader.progress { bytesDownloaded, bytesExpectedToDownload in
            print("\(bytesDownloaded) / \(bytesExpectedToDownload!)")
        }

        let task = Task {
            do {
                try await downloader.completion()
                XCTFail()
            } catch is CancellationError {
                // OK
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        print("cancel")
        downloader.cancel()
        
        try await task.value
    }

    func testFailure() async throws {
        let url1 = URL(string: "https://koherent.org/pi/not-found.txt")!
        let url2 = URL(string: "https://koherent.org/pi/pi100.txt")!
        let file1 = testDirectoryURL.appendingPathComponent("pi10.txt").path
        let file2 = testDirectoryURL.appendingPathComponent("pi100.txt").path
        
        let downloader = Downloader([(from: url1, to: file1), (from: url2, to: file2)])
        
        do {
            try await downloader.completion()
            XCTFail()
        } catch let error as Downloader.ResponseError {
            XCTAssertEqual((error.response as! HTTPURLResponse).statusCode, 404)
        }
    }
}
