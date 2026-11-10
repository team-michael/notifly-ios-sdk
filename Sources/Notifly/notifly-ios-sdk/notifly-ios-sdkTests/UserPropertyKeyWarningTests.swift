import Foundation
import XCTest
@testable import notifly_ios_sdk

final class UserPropertyKeyWarningTests: XCTestCase {
    func testASCIIAndExactReservedKeysDoNotWarn() {
        let keys = [
            "user_name", "User123", "_", "123", "1st_purchase",
            "$email", "$phone_number", "$timezone", "$line_user_id", "$appsflyer_id",
        ]
        XCTAssertNil(UserPropertyKeyPolicy.warningMessage(for: keys))
        XCTAssertNil(UserPropertyKeyPolicy.warningMessage(for: []))
    }

    func testInvalidKeysProduceWarnings() {
        let keys = [
            "", "first.name", "full name", "사용자명", "$custom", "$EMAIL", "a^b", "a-b", "a/b",
            "😀", "é", "Ａ", "name\n", "name\r\n", "name\t", "name\u{00a0}",
        ]
        for key in keys {
            XCTAssertNotNil(UserPropertyKeyPolicy.warningMessage(for: [key]), key)
        }
    }

    func testWarningListsOnlyInvalidKeysInSortedOrder() throws {
        let warning = try XCTUnwrap(
            UserPropertyKeyPolicy.warningMessage(
                for: ["사용자명", "valid_key", "$email", "first.name"]
            )
        )
        XCTAssertEqual(
            warning,
            "Invalid custom user property key(s): [\"first.name\",\"사용자명\"]. "
                + "Only English letters (A-Z, a-z), digits (0-9), and underscores (_) are supported. "
                + "This warning does not block the operation."
        )
    }

    func testControlCharactersAndQuotesAreEscaped() throws {
        let warning = try XCTUnwrap(UserPropertyKeyPolicy.warningMessage(for: ["line\n\t\"key"]))
        XCTAssertFalse(warning.contains("\n"))
        XCTAssertFalse(warning.contains("\t"))
        XCTAssertTrue(warning.contains("line\\n\\t\\\"key"))
    }

    func testExistingInvalidKeysContinueToWarnOnRepeatedCalls() {
        XCTAssertNotNil(UserPropertyKeyPolicy.warningMessage(for: ["old.key"]))
        XCTAssertNotNil(UserPropertyKeyPolicy.warningMessage(for: ["old.key"]))
    }

    func testValuesAndNestedKeysAreNotIncludedInWarning() throws {
        let params: [String: Any] = [
            "first.name": "private-value", "profile": ["nested.key": "한글 $ value"],
            "nullable": NSNull(),
        ]
        let original = params as NSDictionary
        let warning = try XCTUnwrap(UserPropertyKeyPolicy.warningMessage(for: Array(params.keys)))
        XCTAssertFalse(warning.contains("private-value"))
        XCTAssertFalse(warning.contains("nested.key"))
        XCTAssertEqual(params as NSDictionary, original)
    }
}
