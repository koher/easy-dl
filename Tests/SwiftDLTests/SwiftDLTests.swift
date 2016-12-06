import XCTest
@testable import SwiftDL

class SwiftDLTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(SwiftDL().text, "Hello, World!")
    }


    static var allTests : [(String, (SwiftDLTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
