//
//  notifly_ios_sdkTests.swift
//  notifly-ios-sdkTests
//
//  Created by Juyong Kim on 4/15/23.
//

import Combine
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

    func testTrackWithoutTokenPublishesCustomEventAndReleasesWorker() throws {
        let (manager, worker) = makeTrackingManagerForIntegrationTest(deviceToken: nil)

        let payloadReceived = expectation(description: "custom event payload received")
        payloadReceived.assertForOverFulfill = true
        let workerReleased = expectation(description: "following worker task started")
        var payloads: [TrackingEvent] = []
        let payloadsLock = NSLock()
        var cancellables = Set<AnyCancellable>()

        manager.eventRequestPayloadPublisher
            .sink { payload in
                payloadsLock.lock()
                payloads.append(payload)
                payloadsLock.unlock()
                payloadReceived.fulfill()
            }
            .store(in: &cancellables)

        manager.track(
            eventName: "pre_apns_custom_event",
            eventParams: ["source": "cold-start"],
            isInternal: false,
            segmentationEventParamKeys: ["source"]
        )
        worker.addTask { finishTask in
            finishTask()
            workerReleased.fulfill()
        }

        wait(for: [payloadReceived, workerReleased], timeout: 2)

        payloadsLock.lock()
        let capturedPayloads = payloads
        payloadsLock.unlock()
        let payload = try XCTUnwrap(capturedPayloads.first)
        XCTAssertEqual(capturedPayloads.count, 1)
        XCTAssertEqual(payload.records.count, 1)

        let object = try decodeTrackingData(from: try XCTUnwrap(payload.records.first))
        XCTAssertEqual(object["name"] as? String, "pre_apns_custom_event")
        XCTAssertEqual(object["is_internal_event"] as? Bool, false)
        XCTAssertFalse(object.keys.contains("device_token"))
        withExtendedLifetime(cancellables) {}
    }

    func testTrackWithRegisteredTokenPublishesInternalEventAndReleasesWorker() throws {
        let (manager, worker) = makeTrackingManagerForIntegrationTest(
            deviceToken: "registered-fcm-token"
        )

        let payloadReceived = expectation(description: "internal event payload received")
        payloadReceived.assertForOverFulfill = true
        let workerReleased = expectation(description: "following worker task started")
        var payloads: [TrackingEvent] = []
        let payloadsLock = NSLock()
        var cancellables = Set<AnyCancellable>()

        manager.internalEventRequestPayloadPublisher
            .sink { payload in
                payloadsLock.lock()
                payloads.append(payload)
                payloadsLock.unlock()
                payloadReceived.fulfill()
            }
            .store(in: &cancellables)

        manager.track(
            eventName: "registered_internal_event",
            eventParams: nil,
            isInternal: true,
            segmentationEventParamKeys: nil
        )
        worker.addTask { finishTask in
            finishTask()
            workerReleased.fulfill()
        }

        wait(for: [payloadReceived, workerReleased], timeout: 2)

        payloadsLock.lock()
        let capturedPayloads = payloads
        payloadsLock.unlock()
        let payload = try XCTUnwrap(capturedPayloads.first)
        XCTAssertEqual(capturedPayloads.count, 1)
        XCTAssertEqual(payload.records.count, 1)

        let object = try decodeTrackingData(from: try XCTUnwrap(payload.records.first))
        XCTAssertEqual(object["name"] as? String, "registered_internal_event")
        XCTAssertEqual(object["is_internal_event"] as? Bool, true)
        XCTAssertEqual(object["device_token"] as? String, "registered-fcm-token")
        withExtendedLifetime(cancellables) {}
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

    private func makeTrackingManagerForIntegrationTest(deviceToken: String?)
        -> (TrackingManager, NotiflyAsyncWorker)
    {
        let worker = NotiflyAsyncWorker()
        let dependencies = TrackingManager.Dependencies(
            asyncWorker: worker,
            contextProvider: {
                TrackingManager.RuntimeContext(
                    userID: "notifly-user",
                    externalUserID: "external-user",
                    deviceTokenProvider: { deviceToken },
                    processEvent: { _, _, _ in }
                )
            }
        )
        return (
            TrackingManager(projectId: trackingTestProjectID, dependencies: dependencies),
            worker
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
