//
//  SSEClientResponseValidationTests.swift
//  notifly-ios-sdkTests
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEClientResponseValidationTests: XCTestCase {

    func test_204NoContent_isRejectedAndBacksOff() {
        let pb = ProviderBuilder()
        pb.enqueueNoContent(204)
        pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeSSEClient(backoff: [0.02], provider: pb.makeProvider())
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(description: "204 → backoff → second connect") {
            pb.capturedRequestCount >= 2
        }

        XCTAssertTrue(
            recorder.snapshot.contains { state in
                if case .reconnecting = state { return true }
                return false
            },
            "Expected .reconnecting after 204 in \(recorder.snapshot)"
        )

        client.disconnect()
    }

    func test_wrongContentType_isRejectedAndBacksOff() {
        let pb = ProviderBuilder()
        pb.enqueueOpenWithContentType("application/json")
        pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeSSEClient(backoff: [0.02], provider: pb.makeProvider())
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(description: "wrong content-type → backoff → second connect") {
            pb.capturedRequestCount >= 2
        }

        XCTAssertTrue(
            recorder.snapshot.contains { state in
                if case .reconnecting = state { return true }
                return false
            }
        )

        client.disconnect()
    }

    func test_eventStreamWithCharsetParam_isAccepted() {
        let pb = ProviderBuilder()
        pb.enqueueOpenWithContentType("text/event-stream; charset=utf-8")

        let opened = expectation(description: "opened")
        let client = makeSSEClient(provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)
        client.disconnect()
    }
}
