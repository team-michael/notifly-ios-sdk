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
