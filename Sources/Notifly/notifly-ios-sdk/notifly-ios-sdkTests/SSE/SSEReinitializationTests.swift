import Combine
import UIKit
import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEReinitializationTests: XCTestCase {
    private var instances: [Notifly] = []
    private var clients: [SSEClient] = []

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(OfflineAuthorizationProtocol.self)
    }

    override func tearDown() {
        for instance in instances {
            instance.stopSSE()
            instance.unregisterSSELifecycleObservers()
        }
        for client in clients { client.disconnect() }
        clients.removeAll()
        instances.removeAll()
        URLProtocol.unregisterClass(OfflineAuthorizationProtocol.self)
        super.tearDown()
    }

    private func setupSDK(projectId: String = "00000000000000000000000000000001") throws -> Notifly {
        Notifly.setup(projectId: projectId, username: "sse-lifecycle-test", password: "test")
        let instance = try Notifly.main
        instance.userManager.notiflyUserIDCache = "test-user"
        // A late start on the unpatched SDK must fail locally, without a real SSE request.
        instance.auth.authorizationPub = Fail(error: NotiflyError.notInitialized).eraseToAnyPublisher()
        instances.append(instance)
        return instance
    }

    private func attachController(
        to instance: Notifly,
        provider: ProviderBuilder,
        canConnect: @escaping () -> Bool = { true },
        onSync: @escaping (@escaping () -> Void) -> Void = { $0() },
        onEvent: @escaping (String, [String: Any]?) -> Void = { _, _ in },
        scheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void = SSEController.defaultScheduler
    ) -> SSEController {
        let client = makeSSEClient(provider: provider.makeProvider())
        clients.append(client)
        let controller = SSEController(
            sseClient: client, onSyncRequested: onSync, onServerEventTriggered: onEvent,
            canConnect: canConnect, scheduler: scheduler
        )
        instance.sseAccessQueue.sync { instance._sseController = controller }
        return controller
    }

    func test_setupStopsPreviousConnectionAndRemovesObservers() throws {
        let old = try setupSDK()
        let provider = ProviderBuilder()
        provider.enqueueOpen()
        let controller = attachController(to: old, provider: provider)
        old.registerSSELifecycleObservers()
        old.startSSE()
        waitForCondition { controller.sseClient.state == .open }
        XCTAssertEqual(old._sseLifecycleObserverTokens.count, 2)

        let current = try setupSDK(projectId: "00000000000000000000000000000002")

        XCTAssertFalse(old === current)
        XCTAssertEqual(controller.sseClient.state, .stopped)
        XCTAssertNil(old._sseController)
        XCTAssertTrue(old._sseLifecycleObserverTokens.isEmpty)
        XCTAssertFalse(old._sseObserversRegistered)

        let currentProvider = ProviderBuilder()
        currentProvider.enqueueOpen()
        let currentController = attachController(to: current, provider: currentProvider)
        current.startSSE()
        waitForCondition { currentController.sseClient.state == .open }
    }

    func test_replacedInstanceRejectsQueuedInitializationAndUserIdRestart() throws {
        let old = try setupSDK()
        _ = try setupSDK()

        // These are the same entry points used by initialize's queued task and setUserId.
        old.registerSSELifecycleObservers()
        old.startSSE()
        old.restartSSE()

        XCTAssertNil(old._sseController)
        XCTAssertTrue(old._sseLifecycleObserverTokens.isEmpty)
        XCTAssertFalse(old._sseObserversRegistered)
    }

    func test_setupDuringForegroundCheckPreventsLateConnection() throws {
        let old = try setupSDK()
        let provider = ProviderBuilder()
        provider.enqueueOpen()
        let entered = expectation(description: "start is checking foreground")
        let finished = expectation(description: "late start returned")
        let resume = DispatchSemaphore(value: 0)
        let controller = attachController(to: old, provider: provider, canConnect: {
            entered.fulfill()
            _ = resume.wait(timeout: .now() + 3)
            return true
        })
        DispatchQueue.global().async {
            controller.start()
            finished.fulfill()
        }
        wait(for: [entered], timeout: 2)

        _ = try setupSDK()
        resume.signal()
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(controller.sseClient.state, .stopped)
        XCTAssertEqual(provider.capturedRequestCount, 0)
    }

    func test_replacedControllerIgnoresScheduledReconnectAndLateMessages() throws {
        let old = try setupSDK()
        let provider = ProviderBuilder()
        var scheduled: (() -> Void)?
        var syncCount = 0
        var eventCount = 0
        let controller = attachController(
            to: old, provider: provider,
            onSync: { completion in syncCount += 1; completion() },
            onEvent: { _, _ in eventCount += 1 },
            scheduler: { _, work in scheduled = work }
        )
        controller.handleMessage(type: "shutdown", data: "{\"reconnectInMs\":1000}")
        XCTAssertNotNil(scheduled)

        _ = try setupSDK()
        scheduled?()
        controller.handleMessage(type: "ttl-expired", data: "")
        controller.handleMessage(type: "sync", data: "")
        controller.handleMessage(type: "server-event", data: "{\"name\":\"old-project-event\"}")

        XCTAssertEqual(controller.sseClient.state, .stopped)
        XCTAssertEqual(syncCount, 0)
        XCTAssertEqual(eventCount, 0)
    }

    func test_backgroundStopStillAllowsCurrentInstanceToResume() throws {
        let current = try setupSDK()
        let provider = ProviderBuilder()
        provider.enqueueOpen()
        provider.enqueueOpen()
        let controller = attachController(to: current, provider: provider)
        current.registerSSELifecycleObservers()
        current.startSSE()
        waitForCondition { controller.sseClient.state == .open }

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(controller.sseClient.state, .stopped)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        waitForCondition { provider.capturedRequestCount == 2 }
        XCTAssertTrue(current._sseController === controller)
    }

    func test_setupReleasesPreviousClientAfterTaskCancellation() throws {
        let old = try setupSDK()
        let provider = ProviderBuilder()
        provider.enqueueOpen()
        var controller: SSEController? = attachController(to: old, provider: provider)
        weak var oldClient = controller?.sseClient
        old.startSSE()
        waitForCondition { oldClient?.state == .open }
        clients.removeAll()

        _ = try setupSDK()
        controller = nil
        waitForCondition(description: "previous SSE client is released") { oldClient == nil }
    }

    func test_currentInstanceCanRestartWhilePreviousControllerStaysStopped() throws {
        let current = try setupSDK()
        let provider = ProviderBuilder()
        provider.enqueueOpen()
        let previous = attachController(to: current, provider: provider)
        current.startSSE()
        waitForCondition { previous.sseClient.state == .open }

        current.restartSSE()

        XCTAssertNotNil(current._sseController)
        XCTAssertFalse(current._sseController === previous)
        previous.start()
        XCTAssertEqual(previous.sseClient.state, .stopped)
        XCTAssertEqual(provider.capturedRequestCount, 1)
    }
}

private class OfflineAuthorizationProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
