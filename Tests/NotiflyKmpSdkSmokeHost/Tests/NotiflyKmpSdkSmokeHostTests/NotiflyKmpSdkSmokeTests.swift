import NotiflyCore
import XCTest

final class NotiflyKmpSdkSmokeTests: XCTestCase {
    func testCanCallCore() {
        let result = UserIdTransitionPolicy.shared.evaluate(
            previousUserId: nil,
            newUserId: "connectivity-check"
        )

        // Verify runtime linkage only; policy scenarios belong in the KMP SDK.
        XCTAssertNotNil(result)
    }
}
