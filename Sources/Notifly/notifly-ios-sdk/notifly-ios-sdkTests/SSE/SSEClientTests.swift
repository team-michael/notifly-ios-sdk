//
//  SSEClientTests.swift
//  notifly-ios-sdkTests
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEClientTests: XCTestCase {

    // MARK: - 기본

    func test_initialState_isIdle() {
        let pb = ProviderBuilder()
        let client = makeSSEClient(provider: pb.makeProvider())
        XCTAssertEqual(client.state, .idle)
        XCTAssertNil(client.lastEventId)
    }

    func test_connect_transitionsThroughConnectingToOpen() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        let recorder = StateRecorder()
        let openExp = expectation(description: "open")
        let client = makeSSEClient(provider: pb.makeProvider())
        client.onState = { state in
            recorder.append(state)
            if state == .open { openExp.fulfill() }
        }
        client.connect()
        wait(for: [openExp], timeout: 3)

        XCTAssertEqual(recorder.snapshot.first, .connecting)
        XCTAssertTrue(recorder.snapshot.contains(.open))

        client.disconnect()
    }

    func test_connect_emitsMessageOnReceivedEvent() {
        let pb = ProviderBuilder()
        let stream = pb.enqueueOpen()

        let messageExp = expectation(description: "message")
        var receivedType: String?
        var receivedData: String?

        let client = makeSSEClient(provider: pb.makeProvider())
        client.onMessage = { type, data in
            receivedType = type
            receivedData = data
            messageExp.fulfill()
        }
        client.connect()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            stream.writeBlock("event: connected\ndata: {\"projectId\":\"abc\"}\n")
            stream.write("")
        }

        wait(for: [messageExp], timeout: 3)
        XCTAssertEqual(receivedType, "connected")
        XCTAssertEqual(receivedData, "{\"projectId\":\"abc\"}")

        client.disconnect()
    }

    func test_request_buildsBearerAndAcceptHeaders_andURLPath() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        let opened = expectation(description: "open")
        let client = makeSSEClient(token: { "my-token" }, provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)

        let captured = pb.capturedRequests.first
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Last-Event-ID"))
        XCTAssertEqual(captured?.url?.path, "/streams/00000000000000000000000000000abc/user-42")
        XCTAssertEqual(captured?.url?.query, "deviceId=device-1")

        client.disconnect()
    }

    func test_request_omitsDeviceIdQueryWhenNil() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        let opened = expectation(description: "open")
        let client = makeSSEClient(deviceId: nil, provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)

        XCTAssertNil(pb.capturedRequests.first?.url?.query)
        client.disconnect()
    }

    // MARK: - Last-Event-ID 재연결

    func test_reconnect_includesLastEventIdHeader() {
        let pb = ProviderBuilder()
        let firstStream = pb.enqueueOpen()
        pb.enqueueOpen()

        let firstReceived = expectation(description: "first event")
        let client = makeSSEClient(backoff: [0.02], provider: pb.makeProvider())
        client.onMessage = { _, _ in firstReceived.fulfill() }
        client.connect()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            firstStream.writeBlock("id: 42\nevent: sync\ndata: {}\n")
            firstStream.write("")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                firstStream.finish()
            }
        }

        wait(for: [firstReceived], timeout: 3)
        waitForCondition(description: "second request") { pb.capturedRequests.count >= 2 }

        let secondRequest = pb.capturedRequests[1]
        XCTAssertEqual(secondRequest.value(forHTTPHeaderField: "Last-Event-ID"), "42")
        XCTAssertEqual(client.lastEventId, "42")

        client.disconnect()
    }

    // MARK: - HTTP 에러 / 백오프

    func test_httpError_triggersReconnect() {
        let pb = ProviderBuilder()
        pb.enqueueHTTPError(503)
        pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeSSEClient(backoff: [0.02], provider: pb.makeProvider())
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(description: "second request after 503") {
            pb.capturedRequests.count >= 2
        }

        XCTAssertTrue(
            recorder.snapshot.contains { state in
                if case .reconnecting = state { return true }
                return false
            },
            "Expected .reconnecting in \(recorder.snapshot)"
        )

        client.disconnect()
    }

    // MARK: - 멱등성 / disconnect

    func test_connect_isIdempotentWhileConnected() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        let opened = expectation(description: "opened")
        let client = makeSSEClient(provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)

        client.connect()
        client.connect()

        let assertion = expectation(description: "no extra request")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            assertion.fulfill()
        }
        wait(for: [assertion], timeout: 2)
        XCTAssertEqual(pb.capturedRequests.count, 1)

        client.disconnect()
    }

    func test_disconnect_transitionsToStopped() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        let opened = expectation(description: "opened")
        let stopped = expectation(description: "stopped")
        let client = makeSSEClient(provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
            if state == .stopped { stopped.fulfill() }
        }

        client.connect()
        wait(for: [opened], timeout: 3)
        client.disconnect()
        wait(for: [stopped], timeout: 3)
        XCTAssertEqual(client.state, .stopped)
    }

    func test_disconnect_thenConnect_restartsLoop() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()
        pb.enqueueOpen()

        let firstOpen = expectation(description: "first open")
        firstOpen.assertForOverFulfill = false
        let secondOpen = expectation(description: "second open")
        secondOpen.assertForOverFulfill = false

        let client = makeSSEClient(provider: pb.makeProvider())
        let counterQueue = DispatchQueue(label: "test.openCounter")
        var seenOpenCount = 0
        client.onState = { state in
            guard state == .open else { return }
            counterQueue.sync {
                seenOpenCount += 1
                if seenOpenCount == 1 { firstOpen.fulfill() }
                if seenOpenCount == 2 { secondOpen.fulfill() }
            }
        }
        client.connect()
        wait(for: [firstOpen], timeout: 3)
        client.disconnect()
        client.connect()
        wait(for: [secondOpen], timeout: 3)

        XCTAssertEqual(pb.capturedRequests.count, 2)
        client.disconnect()
    }

    // MARK: - Heartbeat watchdog

    func test_heartbeatTimeout_triggersReconnect() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()
        pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeSSEClient(
            backoff: [0.02],
            heartbeatTimeout: 0.3,
            provider: pb.makeProvider()
        )
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(timeout: 5, description: "second request after heartbeat") {
            pb.capturedRequests.count >= 2
        }

        XCTAssertTrue(
            recorder.snapshot.contains { state in
                if case .reconnecting = state { return true }
                return false
            },
            "Expected .reconnecting after heartbeat timeout in \(recorder.snapshot)"
        )

        client.disconnect()
    }

    // MARK: - 토큰 에러

    func test_tokenProviderThrows_loopRecoversOnNextAttempt() {
        let pb = ProviderBuilder()
        pb.enqueueOpen()

        var attempt = 0
        let lock = NSLock()
        let client = makeSSEClient(
            backoff: [0.02],
            token: {
                lock.lock(); defer { lock.unlock() }
                attempt += 1
                if attempt == 1 { throw NSError(domain: "Test", code: 1) }
                return "ok-token"
            },
            provider: pb.makeProvider()
        )

        let opened = expectation(description: "opened on retry")
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)
        // tokenProvider 실패는 request 가 만들어지기 전이라 capturedRequests 1건만.
        XCTAssertEqual(pb.capturedRequests.count, 1)
        client.disconnect()
    }
}
