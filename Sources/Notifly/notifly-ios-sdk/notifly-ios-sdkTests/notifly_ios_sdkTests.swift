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
    private let trackingTestProjectID = "0123456789abcdef0123456789abcdef"
    private let trackingTestTimestamp = 1_788_498_000_000_000

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

    func testCreateTrackingRecordWithoutTokenPreservesEventData() throws {
        let record = try makeTrackingRecord(deviceToken: nil)
        let object = try decodeTrackingData(from: record)

        XCTAssertFalse(object.keys.contains("device_token"))
        XCTAssertEqual(object["name"] as? String, "content_page_view")
        XCTAssertEqual(object["notifly_user_id"] as? String, "notifly-user")
        XCTAssertEqual(object["external_user_id"] as? String, "external-user")
        XCTAssertEqual(object["time"] as? Int, trackingTestTimestamp)
        XCTAssertEqual(object["project_id"] as? String, trackingTestProjectID)
        XCTAssertEqual(object["notifly_device_id"] as? String, record.partitionKey)

        let params = try XCTUnwrap(object["event_params"] as? [String: Any])
        XCTAssertEqual(params["source"] as? String, "onboarding")
        XCTAssertEqual(params["step"] as? Int, 2)
    }

    func testCreateTrackingRecordIncludesAvailableToken() throws {
        let record = try makeTrackingRecord(deviceToken: "valid-fcm-token")
        let object = try decodeTrackingData(from: record)

        XCTAssertEqual(object["device_token"] as? String, "valid-fcm-token")
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

    private func makeTrackingRecord(deviceToken: String?) throws -> TrackingRecord {
        let manager = TrackingManager(projectId: trackingTestProjectID)
        return try XCTUnwrap(
            manager.createTrackingRecord(
                eventName: "content_page_view",
                eventParams: ["source": "onboarding", "step": 2],
                isInternal: false,
                segmentationEventParamKeys: ["source"],
                currentTimestamp: trackingTestTimestamp,
                userID: "notifly-user",
                externalUserID: "external-user",
                deviceToken: deviceToken
            )
        )
    }

    private func decodeTrackingData(from record: TrackingRecord) throws -> [String: Any] {
        let string = try XCTUnwrap(record.data)
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
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

@available(iOSApplicationExtension, unavailable)
private final class LayoutPopup: WebViewModalViewController {
    var showCalls = 0

    override func show(
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) -> Bool {
        showCalls += 1
        return true
    }
}

private struct CornerRadii {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0
}

@available(iOSApplicationExtension, unavailable)
final class WebViewModalLayoutTests: XCTestCase {
    @MainActor
    func testFullscreenTracksContainerWithoutShowingAgain() throws {
        let mounted = try mountPopup(
            properties: popupProperties(width_vw: 100, height_vh: 100),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }
        let popup = mounted.popup
        let originalWebView = popup.webView
        let originalConstraintCount = popup.view.constraints.count
            + popup.webView.constraints.count
        let originalGestureCount = popup.view.gestureRecognizers?.count ?? 0

        for size in [
            CGSize(width: 466, height: 678),
            CGSize(width: 951, height: 669),
            CGSize(width: 678, height: 466),
            CGSize(width: 466, height: 678)
        ] {
            layout(popup, in: size)
            try assertWebView(popup, hasSize: size)
            XCTAssertTrue(popup.webView === originalWebView)
            XCTAssertEqual(
                popup.view.constraints.count + popup.webView.constraints.count,
                originalConstraintCount
            )
            XCTAssertEqual(
                popup.view.gestureRecognizers?.count ?? 0,
                originalGestureCount
            )
        }
        XCTAssertEqual(popup.showCalls, 1)
    }

    @MainActor
    func testFixedDimensionsKeepPriorityAndAreNotClamped() throws {
        let mounted = try mountPopup(
            properties: popupProperties(
                width: 320, width_vw: 100,
                height: 440, height_vh: 100
            ),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }

        for containerSize in [
            CGSize(width: 466, height: 678),
            CGSize(width: 951, height: 669),
            CGSize(width: 250, height: 300)
        ] {
            layout(mounted.popup, in: containerSize)
            try assertWebView(
                mounted.popup,
                hasSize: CGSize(width: 320, height: 440)
            )
        }
    }

    @MainActor
    func testCrossAxisViewportUnitsTrackContainer() throws {
        let mounted = try mountPopup(
            properties: popupProperties(width_vh: 50, height_vw: 25),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }

        layout(mounted.popup, in: CGSize(width: 466, height: 678))
        try assertWebView(
            mounted.popup,
            hasSize: CGSize(width: 339, height: 116.5)
        )

        layout(mounted.popup, in: CGSize(width: 951, height: 669))
        try assertWebView(
            mounted.popup,
            hasSize: CGSize(width: 334.5, height: 237.75)
        )
    }

    @MainActor
    func testMinMaxBoundsRemainAppliedAfterContainerResize() throws {
        let mounted = try mountPopup(
            properties: popupProperties(
                min_width: 300, max_width: 400, width_vw: 50,
                min_height: 250, max_height: 300, height_vh: 50
            ),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }

        layout(mounted.popup, in: CGSize(width: 466, height: 678))
        try assertWebView(
            mounted.popup,
            hasSize: CGSize(width: 300, height: 300)
        )

        layout(mounted.popup, in: CGSize(width: 951, height: 669))
        try assertWebView(
            mounted.popup,
            hasSize: CGSize(width: 400, height: 300)
        )
    }

    @MainActor
    func testRepeatedLayoutKeepsInstalledObjectsAndConstraints() throws {
        let mounted = try mountPopup(
            properties: popupProperties(width_vw: 100, height_vh: 100),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }
        let popup = mounted.popup
        let originalWebView = popup.webView
        let originalMask = try XCTUnwrap(popup.webView.layer.mask as? CAShapeLayer)
        let originalConstraintCount = popup.view.constraints.count
            + popup.webView.constraints.count
        let originalGestureCount = popup.view.gestureRecognizers?.count ?? 0

        for _ in 0 ..< 20 {
            layout(popup, in: CGSize(width: 466, height: 678))
        }

        XCTAssertTrue(popup.webView === originalWebView)
        XCTAssertTrue(popup.webView.layer.mask === originalMask)
        XCTAssertEqual(
            popup.view.constraints.count + popup.webView.constraints.count,
            originalConstraintCount
        )
        XCTAssertEqual(
            popup.view.gestureRecognizers?.count ?? 0,
            originalGestureCount
        )
        XCTAssertEqual(popup.showCalls, 1)
    }

    @MainActor
    func testZeroBoundsDoNotDamageLastValidGeometry() throws {
        let mounted = try mountPopup(
            properties: popupProperties(width_vw: 100, height_vh: 100),
            size: .zero,
            layoutAfterSetup: false
        )
        defer { unmount(mounted) }
        let popup = mounted.popup
        let seedMask = try XCTUnwrap(popup.webView.layer.mask as? CAShapeLayer)
        let seedMaskBounds = try XCTUnwrap(seedMask.path).boundingBoxOfPath

        layout(popup, in: .zero)
        XCTAssertEqual(popup.webView.bounds.size, seedMaskBounds.size)
        XCTAssertTrue(popup.webView.layer.mask === seedMask)
        XCTAssertEqual(seedMask.path?.boundingBoxOfPath, seedMaskBounds)

        layout(popup, in: CGSize(width: 466, height: 678))
        try assertWebView(
            popup,
            hasSize: CGSize(width: 466, height: 678)
        )
        XCTAssertTrue(popup.webView.layer.mask === seedMask)
        XCTAssertEqual(popup.showCalls, 1)
    }

    @MainActor
    func testMissingRadiiKeepMaskNilAcrossResize() throws {
        let mounted = try mountPopup(
            properties: [
                "template_name": "layout-test",
                "position": "bottom",
                "width_vw": 100,
                "height_vh": 100
            ],
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }

        XCTAssertNil(mounted.popup.webView.layer.mask)
        layout(mounted.popup, in: CGSize(width: 951, height: 669))
        XCTAssertNil(mounted.popup.webView.layer.mask)
        XCTAssertEqual(
            mounted.popup.webView.bounds.size,
            CGSize(width: 951, height: 669)
        )
    }

    @MainActor
    func testAsymmetricRadiiAndPositionRemainCorrect() throws {
        try assertAsymmetricRadii(position: "center")
        try assertAsymmetricRadii(position: "bottom")
    }

    @MainActor
    private func assertAsymmetricRadii(position: String) throws {
        let mounted = try mountPopup(
            properties: popupProperties(
                position: position,
                width_vw: 80,
                height_vh: 70,
                radii: CornerRadii(topLeft: 4, topRight: 8, bottomLeft: 12, bottomRight: 16)
            ),
            size: CGSize(width: 466, height: 678)
        )
        defer { unmount(mounted) }

        for containerSize in [
            CGSize(width: 951, height: 669),
            CGSize(width: 466, height: 678)
        ] {
            layout(mounted.popup, in: containerSize)
            let webView = mounted.popup.webView
            let expectedSize = CGSize(
                width: containerSize.width * 0.8,
                height: containerSize.height * 0.7
            )
            try assertWebView(webViewController: mounted.popup, hasSize: expectedSize)
            XCTAssertEqual(webView.frame.midX, mounted.popup.view.bounds.midX, accuracy: 0.5)
            if position == "bottom" {
                XCTAssertEqual(webView.frame.maxY, mounted.popup.view.bounds.maxY, accuracy: 0.5)
            } else {
                XCTAssertEqual(webView.frame.midY, mounted.popup.view.bounds.midY, accuracy: 0.5)
            }

            let path = try XCTUnwrap((webView.layer.mask as? CAShapeLayer)?.path)
            let width = webView.bounds.width
            let height = webView.bounds.height
            XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
            XCTAssertTrue(path.contains(CGPoint(x: 2, y: 2)))
            XCTAssertFalse(path.contains(CGPoint(x: width - 2, y: 2)))
            XCTAssertTrue(path.contains(CGPoint(x: width - 3, y: 3)))
            XCTAssertFalse(path.contains(CGPoint(x: 3, y: height - 3)))
            XCTAssertTrue(path.contains(CGPoint(x: 4, y: height - 4)))
            XCTAssertFalse(path.contains(CGPoint(x: width - 4, y: height - 4)))
            XCTAssertTrue(path.contains(CGPoint(x: width - 5, y: height - 5)))
        }
    }

    @MainActor
    private func mountPopup(
        properties: [String: Any],
        size: CGSize,
        layoutAfterSetup: Bool = true
    ) throws -> (popup: LayoutPopup, window: UIWindow) {
        let popup = LayoutPopup(nibName: nil, bundle: nil)
        popup.modalProps = try XCTUnwrap(ModalProperties(properties: properties))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
        let host = UIViewController()
        window.rootViewController = host
        window.addSubview(host.view)
        host.addChild(popup)
        host.view.addSubview(popup.view)
        popup.didMove(toParent: host)
        popup.view.frame = CGRect(origin: .zero, size: size)
        XCTAssertTrue(popup.view.window === window)
        popup.viewWillLayoutSubviews()
        XCTAssertTrue(popup.setupUI())
        if layoutAfterSetup {
            layout(popup, in: size)
        }
        return (popup, window)
    }

    @MainActor
    private func unmount(_ mounted: (popup: LayoutPopup, window: UIWindow)) {
        let popup = mounted.popup
        popup.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "notiflyInAppMessageEventHandler")
        popup.webView.navigationDelegate = nil
        popup.willMove(toParent: nil)
        popup.view.removeFromSuperview()
        popup.removeFromParent()
        mounted.window.rootViewController = nil
    }

    @MainActor
    private func layout(_ popup: LayoutPopup, in size: CGSize) {
        popup.view.frame.size = size
        popup.view.setNeedsLayout()
        popup.view.layoutIfNeeded()
    }

    @MainActor
    private func assertWebView(
        _ popup: LayoutPopup,
        hasSize expectedSize: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertWebView(
            webViewController: popup,
            hasSize: expectedSize,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertWebView(
        webViewController popup: LayoutPopup,
        hasSize expectedSize: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            popup.webView.bounds.width,
            expectedSize.width,
            accuracy: 0.5,
            file: file,
            line: line
        )
        XCTAssertEqual(
            popup.webView.bounds.height,
            expectedSize.height,
            accuracy: 0.5,
            file: file,
            line: line
        )
        let mask = try XCTUnwrap(
            popup.webView.layer.mask as? CAShapeLayer,
            file: file,
            line: line
        )
        let rect = try XCTUnwrap(mask.path, file: file, line: line).boundingBoxOfPath
        XCTAssertEqual(rect.width, expectedSize.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(rect.height, expectedSize.height, accuracy: 0.5, file: file, line: line)
    }

    private func popupProperties(
        position: String = "bottom",
        width: CGFloat? = nil,
        min_width: CGFloat? = nil,
        max_width: CGFloat? = nil,
        width_vw: CGFloat? = nil,
        width_vh: CGFloat? = nil,
        height: CGFloat? = nil,
        min_height: CGFloat? = nil,
        max_height: CGFloat? = nil,
        height_vw: CGFloat? = nil,
        height_vh: CGFloat? = nil,
        radii: CornerRadii = CornerRadii()
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "template_name": "layout-test",
            "position": position,
            "borderTopLeftRadius": Double(radii.topLeft),
            "borderTopRightRadius": Double(radii.topRight),
            "borderBottomLeftRadius": Double(radii.bottomLeft),
            "borderBottomRightRadius": Double(radii.bottomRight)
        ]
        properties["width"] = width.map(Double.init)
        properties["min_width"] = min_width.map(Double.init)
        properties["max_width"] = max_width.map(Double.init)
        properties["width_vw"] = width_vw.map(Double.init)
        properties["width_vh"] = width_vh.map(Double.init)
        properties["height"] = height.map(Double.init)
        properties["min_height"] = min_height.map(Double.init)
        properties["max_height"] = max_height.map(Double.init)
        properties["height_vw"] = height_vw.map(Double.init)
        properties["height_vh"] = height_vh.map(Double.init)
        return properties
    }
}
