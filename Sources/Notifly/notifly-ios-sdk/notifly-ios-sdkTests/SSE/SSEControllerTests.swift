//
//  SSEControllerTests.swift
//  notifly-ios-sdkTests
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEControllerTests: XCTestCase {

    // MARK: - Helpers

    private final class Spy: @unchecked Sendable {
        let lock = NSLock()
        private var _syncRequestedCount = 0
        private var _eventCalls: [(String, [String: Any]?)] = []
        private var _scheduledTasks: [(TimeInterval, () -> Void)] = []

        var syncRequestedCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _syncRequestedCount
        }
        var eventCalls: [(String, [String: Any]?)] {
            lock.lock(); defer { lock.unlock() }
            return _eventCalls
        }

        func recordSync() {
            lock.lock(); defer { lock.unlock() }
            _syncRequestedCount += 1
        }
        func recordEvent(_ name: String, _ params: [String: Any]?) {
            lock.lock(); defer { lock.unlock() }
            _eventCalls.append((name, params))
        }
        func scheduleTask(_ delay: TimeInterval, _ work: @escaping () -> Void) {
            lock.lock()
            _scheduledTasks.append((delay, work))
            lock.unlock()
        }
        /// 디바운스 윈도우 만료를 흉내내기 위해 즉시 실행.
        func flushScheduled() {
            lock.lock()
            let tasks = _scheduledTasks
            _scheduledTasks.removeAll()
            lock.unlock()
            for (_, work) in tasks { work() }
        }
    }

    private func makeDummySSEClient() -> SSEClient {
        // streamLineProvider 는 connect() 호출 시에만 발동.
        // 본 테스트는 connect() 를 호출하지 않으므로 throw stub 으로 둔다.
        return SSEClient(
            projectId: "00000000000000000000000000000abc",
            notiflyUserId: "u",
            deviceId: nil,
            tokenProvider: { "t" },
            baseURLString: "https://test.local/streams",
            streamLineProvider: { _ in
                throw NSError(domain: "should-not-be-called", code: 0)
            }
        )
    }

    private func makeController(
        spy: Spy,
        debounce: TimeInterval = 1.0
    ) -> SSEController {
        let client = makeDummySSEClient()
        return SSEController(
            sseClient: client,
            onSyncRequested: { completion in
                spy.recordSync()
                completion()
            },
            onServerEventTriggered: { name, params in
                spy.recordEvent(name, params)
            },
            syncDebounceInterval: debounce,
            scheduler: { delay, work in
                spy.scheduleTask(delay, work)
            }
        )
    }

    // MARK: - sync routing + 디바운스

    func test_sync_singleMessage_triggersSyncOnce() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 1)
    }

    func test_sync_burstWithinDebounce_triggersSyncOnce() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "sync", data: "{}")
        controller.handleMessage(type: "sync", data: "{}")
        controller.handleMessage(type: "sync", data: "{}")

        XCTAssertEqual(spy.syncRequestedCount, 1)
    }

    func test_sync_blockedByInFlightEvenAfterDebounceWindow() {
        let spy = Spy()
        var heldCompletion: (() -> Void)?
        let controller = SSEController(
            sseClient: makeDummySSEClient(),
            onSyncRequested: { completion in
                spy.recordSync()
                heldCompletion = completion
            },
            onServerEventTriggered: { _, _ in },
            syncDebounceInterval: 1.0,
            scheduler: { delay, work in spy.scheduleTask(delay, work) }
        )

        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 1)

        spy.flushScheduled()
        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 1)

        heldCompletion?()
        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 2)
    }

    func test_sync_afterDebounceWindow_triggersAgain() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 1)

        spy.flushScheduled()

        controller.handleMessage(type: "sync", data: "{}")
        XCTAssertEqual(spy.syncRequestedCount, 2)
    }

    // MARK: - server-event routing

    func test_serverEvent_routesNameAndParams() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(
            type: "server-event",
            data: "{\"name\":\"order\",\"eventParams\":{\"price\":1000}}"
        )

        XCTAssertEqual(spy.eventCalls.count, 1)
        XCTAssertEqual(spy.eventCalls.first?.0, "order")
        XCTAssertEqual((spy.eventCalls.first?.1?["price"] as? NSNumber)?.intValue, 1000)
    }

    func test_serverEvent_malformed_doesNotTrigger() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "server-event", data: "not json")
        XCTAssertEqual(spy.eventCalls.count, 0)
    }

    // MARK: - unknown / connected

    func test_unknownType_isIgnored() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "weird", data: "")
        XCTAssertEqual(spy.syncRequestedCount, 0)
        XCTAssertEqual(spy.eventCalls.count, 0)
    }

    func test_connected_exitsFallbackAndMarksOpen() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleStateChange(.reconnecting(attempt: 3))
        XCTAssertEqual(controller.mode, .fallback)

        // connected 메시지가 .sse 복귀 + hasReachedOpen 셋팅을 둘 다 한다.
        controller.handleMessage(type: "connected", data: "{}")
        XCTAssertEqual(controller.mode, .sse)

        controller.handleStateChange(.reconnecting(attempt: 10))
        XCTAssertEqual(controller.mode, .sse)
    }

    // MARK: - Fallback 진입 / 비진입

    func test_reconnecting_attempt3_withoutPriorOpen_entersFallback() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleStateChange(.reconnecting(attempt: 1))
        controller.handleStateChange(.reconnecting(attempt: 2))
        controller.handleStateChange(.reconnecting(attempt: 3))

        XCTAssertEqual(controller.mode, .fallback)
    }

    func test_reconnecting_below3_doesNotEnterFallback() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleStateChange(.reconnecting(attempt: 1))
        controller.handleStateChange(.reconnecting(attempt: 2))

        XCTAssertEqual(controller.mode, .sse)
    }

    func test_openReachedThenManyReconnects_doesNotEnterFallback() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleStateChange(.open)
        controller.handleStateChange(.reconnecting(attempt: 5))
        controller.handleStateChange(.reconnecting(attempt: 10))

        XCTAssertEqual(controller.mode, .sse)
    }

    func test_connectedMessage_marksOpenSoFallbackBlocked() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleMessage(type: "connected", data: "{}")
        controller.handleStateChange(.reconnecting(attempt: 5))

        XCTAssertEqual(controller.mode, .sse)
    }

    func test_fallbackEntered_thenOpenReached_returnsToSseMode() {
        let spy = Spy()
        let controller = makeController(spy: spy)

        controller.handleStateChange(.reconnecting(attempt: 3))
        XCTAssertEqual(controller.mode, .fallback)

        controller.handleStateChange(.open)
        XCTAssertEqual(controller.mode, .sse)
    }
}
