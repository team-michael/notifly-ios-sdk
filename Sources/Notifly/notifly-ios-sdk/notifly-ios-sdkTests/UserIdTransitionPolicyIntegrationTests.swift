import NotiflyKMP
import XCTest

final class UserIdTransitionPolicyIntegrationTests: XCTestCase {
    func testAnonymousToIdentifiedRequestsSyncAndMerge() {
        let decision = UserIdTransitionPolicy.shared.evaluate(
            previousUserId: nil,
            newUserId: "user-1"
        )

        XCTAssertTrue(decision.changed)
        XCTAssertTrue(decision.shouldSync)
        XCTAssertTrue(decision.shouldMerge)
        XCTAssertFalse(decision.shouldClear)
    }

    func testIdentifiedToAnonymousRequestsSyncAndClear() {
        let decision = UserIdTransitionPolicy.shared.evaluate(
            previousUserId: "user-1",
            newUserId: nil
        )

        XCTAssertTrue(decision.changed)
        XCTAssertTrue(decision.shouldSync)
        XCTAssertFalse(decision.shouldMerge)
        XCTAssertTrue(decision.shouldClear)
    }
}
