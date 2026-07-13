//
//  notifly_ios_sdkTests.swift
//  notifly-ios-sdkTests
//
//  Created by Juyong Kim on 4/15/23.
//

import UIKit
import XCTest
@testable import notifly_ios_sdk

class notifly_ios_sdkTests: XCTestCase {
    func testSessionStartIsAllowedOnlyWhenApplicationIsActive() {
        XCTAssertTrue(
            TrackingManager.canTrackSessionStart(applicationState: .active)
        )
        XCTAssertFalse(
            TrackingManager.canTrackSessionStart(applicationState: .inactive)
        )
        XCTAssertFalse(
            TrackingManager.canTrackSessionStart(applicationState: .background)
        )
    }
}
