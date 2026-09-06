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

    override func tearDown() {
        WebViewModalViewController.openedInAppMessageCount = 0
        super.tearDown()
    }

    func testExternalDismissReleasesInAppMessageGate() {
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = true
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 0)
    }

    func testDisappearanceWithoutDismissKeepsInAppMessageGate() {
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = false
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 1)
    }

}

private final class LifecycleStateWebViewModalViewController:
    WebViewModalViewController
{
    var stubIsBeingDismissed = false

    override var isBeingDismissed: Bool {
        stubIsBeingDismissed
    }
}
