import Foundation
import XCTest
@testable import notifly_ios_sdk

final class UserPropertyKeyWarningTests: XCTestCase {
    func testSwiftKeysReachSharedPolicyWithoutWarning() {
        XCTAssertNil(UserPropertyKeyWarning.message(for: ["user_name", "$email"]))
        XCTAssertNil(UserPropertyKeyWarning.message(for: []))
    }

    func testSwiftBridgeReturnsEscapedWarningAndPreservesInput() throws {
        let params: [String: Any] = [
            "first.name": "private-value", "name\n\"": NSNull(),
            "profile": ["nested.key": "unchanged"],
        ]
        let original = params as NSDictionary

        let warning = try XCTUnwrap(UserPropertyKeyWarning.message(for: Array(params.keys)))

        XCTAssertTrue(warning.contains("[\"first.name\",\"name\\n\\\"\"]"))
        XCTAssertTrue(warning.contains("does not block"))
        XCTAssertFalse(warning.contains("private-value"))
        XCTAssertFalse(warning.contains("nested.key"))
        XCTAssertEqual(params as NSDictionary, original)
    }
}
