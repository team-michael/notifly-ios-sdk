//
//  SSEClientTests.swift
//  notifly-ios-sdkTests
//
//  SSEClient 통합 테스트 — streamLineProvider 를 주입하여 결정적 라인 입력으로 검증.
//  실제 URLSession.bytes 와의 결합은 production 에서만 사용하며 본 테스트는 그 위층의 동작을 검증한다.
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEClientTests: XCTestCase {

    // MARK: - Helpers

    /// 단일 connect 시도에 대한 stream 시나리오. 테스트가 lines 를 푸시한다.
    private final class TestStream: @unchecked Sendable {
        let continuation: AsyncThrowingStream<String, Error>.Continuation
        let stream: AsyncThrowingStream<String, Error>

        init() {
            var contRef: AsyncThrowingStream<String, Error>.Continuation!
            self.stream = AsyncThrowingStream<String, Error> { c in contRef = c }
            self.continuation = contRef
        }

        func write(_ line: String) {
            continuation.yield(line)
        }

        func writeBlock(_ block: String) {
            // "event: x\ndata: y\n\n" 같은 raw block 을 라인 단위로 분할하여 푸시.
            for line in block.components(separatedBy: "\n") {
                continuation.yield(line)
            }
        }

        func finish() {
            continuation.finish()
        }

        func fail(_ error: Error) {
            continuation.finish(throwing: error)
        }
    }

    /// connect 시도마다 다음 시나리오를 반환하는 provider 빌더.
    /// 각 시나리오는 (statusCode, optional preset stream) 또는 외부 제어용 TestStream 을 사용.
    private final class ProviderBuilder: @unchecked Sendable {
        struct Scenario {
            var statusCode: Int = 200
            var contentType: String = "text/event-stream"
            var stream: TestStream?
        }

        private let lock = NSLock()
        private var scenarios: [Scenario] = []
        private(set) var capturedRequests: [URLRequest] = []
        var onRequest: ((URLRequest) -> Void)?

        func enqueue(_ scenario: Scenario) {
            lock.lock(); defer { lock.unlock() }
            scenarios.append(scenario)
        }

        func enqueueOpen(stream: TestStream = TestStream()) -> TestStream {
            enqueue(Scenario(statusCode: 200, stream: stream))
            return stream
        }

        func enqueueOpenWithContentType(_ contentType: String, stream: TestStream = TestStream()) -> TestStream {
            enqueue(Scenario(statusCode: 200, contentType: contentType, stream: stream))
            return stream
        }

        func enqueueHTTPError(_ code: Int) {
            enqueue(Scenario(statusCode: code, stream: nil))
        }

        /// non-200 success (204 등). body 비어있는 stream 으로 즉시 finish.
        func enqueueNoContent(_ code: Int = 204) {
            enqueue(Scenario(statusCode: code, stream: nil))
        }

        func makeProvider() -> SSEClient.StreamLineProvider {
            return { [weak self] request in
                guard let self = self else { throw SSEClient.ConnectionError.invalidResponse }
                self.lock.lock()
                self.capturedRequests.append(request)
                let cb = self.onRequest
                let scenario = self.scenarios.isEmpty
                    ? Scenario(statusCode: 500, stream: nil)
                    : self.scenarios.removeFirst()
                self.lock.unlock()
                cb?(request)

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: scenario.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": scenario.contentType]
                )!
                let stream = scenario.stream?.stream ?? AsyncThrowingStream<String, Error> { c in
                    c.finish()
                }
                return (response, stream)
            }
        }
    }

    private func makeClient(
        deviceId: String? = "device-1",
        backoff: [TimeInterval] = [0.05],
        heartbeatTimeout: TimeInterval = SSEClient.defaultHeartbeatTimeout,
        token: @escaping () async throws -> String = { "test-token" },
        provider: @escaping SSEClient.StreamLineProvider
    ) -> SSEClient {
        return SSEClient(
            projectId: "00000000000000000000000000000abc",
            notiflyUserId: "user-42",
            deviceId: deviceId,
            tokenProvider: token,
            baseURLString: "https://test.local/streams",
            backoffSchedule: backoff,
            heartbeatTimeout: heartbeatTimeout,
            streamLineProvider: provider,
            jitterProvider: { 1.0 }
        )
    }

    private func waitForCondition(
        timeout: TimeInterval = 3,
        description: String = "condition",
        _ check: @escaping () -> Bool
    ) {
        let exp = expectation(description: description)
        let queue = DispatchQueue.global()
        var fulfilled = false
        let lock = NSLock()
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            queue.asyncAfter(deadline: .now() + 0.02) {
                lock.lock()
                if fulfilled {
                    lock.unlock()
                    return
                }
                lock.unlock()
                if check() {
                    lock.lock()
                    if !fulfilled {
                        fulfilled = true
                        lock.unlock()
                        exp.fulfill()
                    } else {
                        lock.unlock()
                    }
                    return
                }
                if Date() < deadline {
                    tick()
                } else {
                    lock.lock()
                    if !fulfilled {
                        fulfilled = true
                        lock.unlock()
                        exp.fulfill()
                    } else {
                        lock.unlock()
                    }
                }
            }
        }
        tick()
        wait(for: [exp], timeout: timeout + 1)
    }

    // MARK: - 기본

    func test_initialState_isIdle() {
        let pb = ProviderBuilder()
        let client = makeClient(provider: pb.makeProvider())
        XCTAssertEqual(client.state, .idle)
        XCTAssertNil(client.lastEventId)
    }

    func test_connect_transitionsThroughConnectingToOpen() {
        let pb = ProviderBuilder()
        _ = pb.enqueueOpen()  // connect 시도 시 .open

        let recorder = StateRecorder()
        let openExp = expectation(description: "open")
        let client = makeClient(provider: pb.makeProvider())
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

        let client = makeClient(provider: pb.makeProvider())
        client.onMessage = { type, data in
            receivedType = type
            receivedData = data
            messageExp.fulfill()
        }
        client.connect()

        // .open 이 된 시점에 라인 푸시.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            stream.writeBlock("event: connected\ndata: {\"projectId\":\"abc\"}\n")
            stream.write("")  // dispatch trigger
        }

        wait(for: [messageExp], timeout: 3)
        XCTAssertEqual(receivedType, "connected")
        XCTAssertEqual(receivedData, "{\"projectId\":\"abc\"}")

        client.disconnect()
    }

    func test_request_buildsBearerAndAcceptHeaders_andURLPath() {
        let pb = ProviderBuilder()
        _ = pb.enqueueOpen()

        let opened = expectation(description: "open")
        let client = makeClient(token: { "my-token" }, provider: pb.makeProvider())
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
        _ = pb.enqueueOpen()

        let opened = expectation(description: "open")
        let client = makeClient(deviceId: nil, provider: pb.makeProvider())
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
        _ = pb.enqueueOpen()  // 2차 연결

        let firstReceived = expectation(description: "first event")
        let client = makeClient(backoff: [0.02], provider: pb.makeProvider())
        client.onMessage = { _, _ in firstReceived.fulfill() }
        client.connect()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            firstStream.writeBlock("id: 42\nevent: sync\ndata: {}\n")
            firstStream.write("")
            // stream 종료 → 재연결 유도
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

    // MARK: - 백오프 / HTTP 에러

    func test_httpError_triggersReconnect() {
        let pb = ProviderBuilder()
        pb.enqueueHTTPError(503)
        _ = pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeClient(backoff: [0.02], provider: pb.makeProvider())
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

    func test_204NoContent_isRejectedAndBacksOff() {
        let pb = ProviderBuilder()
        pb.enqueueNoContent(204)
        _ = pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeClient(backoff: [0.02], provider: pb.makeProvider())
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(description: "204 → backoff → second connect") {
            pb.capturedRequests.count >= 2
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
        _ = pb.enqueueOpenWithContentType("application/json")
        _ = pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeClient(backoff: [0.02], provider: pb.makeProvider())
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(description: "wrong content-type → backoff → second connect") {
            pb.capturedRequests.count >= 2
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
        _ = pb.enqueueOpenWithContentType("text/event-stream; charset=utf-8")

        let opened = expectation(description: "opened")
        let client = makeClient(provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)
        client.disconnect()
    }

    // MARK: - 멱등성 / disconnect

    func test_connect_isIdempotentWhileConnected() {
        let pb = ProviderBuilder()
        _ = pb.enqueueOpen()

        let opened = expectation(description: "opened")
        let client = makeClient(provider: pb.makeProvider())
        client.onState = { state in
            if state == .open { opened.fulfill() }
        }
        client.connect()
        wait(for: [opened], timeout: 3)

        client.connect()
        client.connect()

        // 짧게 대기 후 추가 요청 없는지 확인
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
        _ = pb.enqueueOpen()

        let opened = expectation(description: "opened")
        let stopped = expectation(description: "stopped")
        let client = makeClient(provider: pb.makeProvider())
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
        _ = pb.enqueueOpen()
        _ = pb.enqueueOpen()

        let firstOpen = expectation(description: "first open")
        firstOpen.assertForOverFulfill = false
        let secondOpen = expectation(description: "second open")
        secondOpen.assertForOverFulfill = false

        let client = makeClient(provider: pb.makeProvider())
        // onState 는 main queue 로 dispatch 되지만 가독성/안전성을 위해 명시 동기화.
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
        // 1차: open 유지하되 라인 미푸시 → watchdog 가 끊는다.
        _ = pb.enqueueOpen()
        // 2차: 재연결 검증용
        _ = pb.enqueueOpen()

        let recorder = StateRecorder()
        let client = makeClient(
            backoff: [0.02],
            heartbeatTimeout: 0.3,
            provider: pb.makeProvider()
        )
        client.onState = { recorder.append($0) }
        client.connect()

        waitForCondition(timeout: 5, description: "second request after heartbeat") {
            pb.capturedRequests.count >= 2
        }

        // heartbeat timeout 으로 .reconnecting 상태가 한 번 이상 거쳐갔는지 검증.
        XCTAssertTrue(
            recorder.snapshot.contains { state in
                if case .reconnecting = state { return true }
                return false
            },
            "Expected .reconnecting after heartbeat timeout in \(recorder.snapshot)"
        )

        client.disconnect()
    }

    // MARK: - 토큰 / URL 에러

    func test_tokenProviderThrows_loopRecoversOnNextAttempt() {
        let pb = ProviderBuilder()
        _ = pb.enqueueOpen()  // 두 번째 시도에서는 정상 open

        var attempt = 0
        let lock = NSLock()
        let client = makeClient(
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
        XCTAssertEqual(pb.capturedRequests.count, 1)  // token 실패 시점에는 request 안 만들어짐
        client.disconnect()
    }
}

// MARK: - Test Utilities

@available(iOSApplicationExtension, unavailable)
final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [SSEClient.State] = []

    func append(_ s: SSEClient.State) {
        lock.lock(); defer { lock.unlock() }
        states.append(s)
    }

    var snapshot: [SSEClient.State] {
        lock.lock(); defer { lock.unlock() }
        return states
    }
}
