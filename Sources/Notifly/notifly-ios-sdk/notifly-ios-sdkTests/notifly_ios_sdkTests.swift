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

    func testExternalDismissReleasesInAppMessageGate() {
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = true
        popup.stubPresentingViewController = UIViewController()
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 0)
    }

    func testRootReplacementReleasesInAppMessageGate() {
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = false
        popup.stubPresentingViewController = nil
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 0)
    }

    func testPresentingControllerDismissReleasesInAppMessageGate() {
        let presenter = LifecycleStateViewController()
        presenter.stubIsBeingDismissed = true
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = false
        popup.stubPresentingViewController = presenter
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 0)
    }

    func testTemporaryCoverageKeepsInAppMessageGate() {
        let popup = LifecycleStateWebViewModalViewController()
        popup.stubIsBeingDismissed = false
        popup.stubPresentingViewController = UIViewController()
        WebViewModalViewController.openedInAppMessageCount = 1

        popup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 1)
    }

    func testRepeatedCleanupFromOldControllerDoesNotReleaseNewGate() {
        let oldPopup = LifecycleStateWebViewModalViewController()
        oldPopup.stubIsBeingDismissed = true
        oldPopup.stubPresentingViewController = UIViewController()
        WebViewModalViewController.openedInAppMessageCount = 1

        oldPopup.viewDidDisappear(false)
        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 0)

        WebViewModalViewController.openedInAppMessageCount = 1
        oldPopup.viewDidDisappear(false)

        XCTAssertEqual(WebViewModalViewController.openedInAppMessageCount, 1)
    }
}

private final class LifecycleStateViewController: UIViewController {
    var stubIsBeingDismissed = false

    override var isBeingDismissed: Bool {
        stubIsBeingDismissed
    }
}

private final class LifecycleStateWebViewModalViewController:
    WebViewModalViewController
{
    var stubIsBeingDismissed = false
    var stubPresentingViewController: UIViewController?

    override var isBeingDismissed: Bool {
        stubIsBeingDismissed
    }

    override var presentingViewController: UIViewController? {
        stubPresentingViewController
    }
}
