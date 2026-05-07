//
//  SSEClientTestSupport.swift
//  notifly-ios-sdkTests
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class TestStream: @unchecked Sendable {
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

@available(iOSApplicationExtension, unavailable)
struct ProviderScenario {
    var statusCode: Int = 200
    var contentType: String = "text/event-stream"
    var stream: TestStream?
}

@available(iOSApplicationExtension, unavailable)
final class ProviderBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var scenarios: [ProviderScenario] = []
    private var _capturedRequests: [URLRequest] = []
    var onRequest: ((URLRequest) -> Void)?

    var capturedRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _capturedRequests.count
    }

    var capturedRequestsSnapshot: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _capturedRequests
    }

    func enqueue(_ scenario: ProviderScenario) {
        lock.lock(); defer { lock.unlock() }
        scenarios.append(scenario)
    }

    @discardableResult
    func enqueueOpen(stream: TestStream = TestStream()) -> TestStream {
        enqueue(ProviderScenario(statusCode: 200, stream: stream))
        return stream
    }

    @discardableResult
    func enqueueOpenWithContentType(_ contentType: String, stream: TestStream = TestStream()) -> TestStream {
        enqueue(ProviderScenario(statusCode: 200, contentType: contentType, stream: stream))
        return stream
    }

    func enqueueHTTPError(_ code: Int) {
        enqueue(ProviderScenario(statusCode: code, stream: nil))
    }

    func enqueueNoContent(_ code: Int = 204) {
        enqueue(ProviderScenario(statusCode: code, stream: nil))
    }

    func makeProvider() -> SSEClient.StreamLineProvider {
        return { [weak self] request in
            guard let self = self else { throw SSEClient.ConnectionError.invalidResponse }
            self.lock.lock()
            self._capturedRequests.append(request)
            let cb = self.onRequest
            let scenario = self.scenarios.isEmpty
                ? ProviderScenario(statusCode: 500, stream: nil)
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

@available(iOSApplicationExtension, unavailable)
extension XCTestCase {

    func makeSSEClient(
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

    func waitForCondition(
        timeout: TimeInterval = 3,
        description: String = "condition",
        file: StaticString = #file,
        line: UInt = #line,
        _ check: @escaping () -> Bool
    ) {
        let exp = expectation(description: description)
        let queue = DispatchQueue.global()
        let lock = NSLock()
        var fulfilled = false
        var timedOut = false
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
                        timedOut = true
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
        lock.lock()
        let didTimeOut = timedOut
        lock.unlock()
        if didTimeOut {
            XCTFail("waitForCondition timed out: \(description)", file: file, line: line)
        }
    }
}
