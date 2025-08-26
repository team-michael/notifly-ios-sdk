//
//  NotificationManagerLegacyBehaviorTests.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/25/25.
//
import XCTest
import Combine
@testable import notifly_ios_sdk

/// NotificationsManager 레거시 동작(핫픽스 이전)을 재현/검증하는 테스트 모음.
/// IMPORTANT:
/// - 이 스위트는 DEBUG + legacy 모드에서 실행해야 합니다.
/// - 이 스위트에서의 PASS는 "레거시의 문제적 동작이 재현되었다"를 의미합니다.
///   즉, PASS == 불안정성 입증.
/// - 핫픽스/리팩터 모드(legacy OFF)에서는 본 테스트가 FAIL(또는 SKIP)되는 것이 정상입니다.
final class NotificationsManagerLegacyBehaviorTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    private var notifly: Notifly!
    private var mgr: NotificationsManager!

    override func setUp() {
        super.setUp()
        // 메인 인스턴스가 내부적으로 참조되므로 반드시 main 기반으로 테스트합니다.
        Notifly.setup(projectId: "legacy_test_project", username: "legacy_org", password: "pw")
        #if DEBUG
        NotificationsManager.debugLegacyModeEnabled = false
        #endif
        notifly = try? Notifly.main
        mgr = notifly.notificationsManager
        print("SETUP: legacy mode = \(NotificationsManager.debugLegacyModeEnabled)")
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Test 1: FCM 최대 재시도 초과 → 퍼블리셔 poison(Fail) 상태 재현

    /// PURPOSE:
    /// - 레거시에서는 FCM 최대 재시도 초과 시 deviceToken 퍼블리셔가 Fail로 고정(poison)되어
    ///   이후 회복(늦은 성공)이 불가능해지는 문제를 재현합니다.
    ///
    /// LEGACY PASS MEANS:
    /// - 구독 즉시 실패(completion .failure)가 발생 → poison 상태 입증.
    ///
    /// IF FAILS:
    /// - 레거시 스위치 미적용, 타이밍 문제, 혹은 코드가 이미 핫픽스 동작으로 전환되었을 가능성.
    func test_Legacy_FCM_MaxRetry_PublisherPoisoned() {
        print("TEST1: simulate FCM max-retry exceeded (legacy poison)")

        mgr.test_simulateFCMMaxRetryExceeded()
        XCTAssertEqual(mgr.test_getFCMState(), .failed, "FCM state should be .failed in legacy")

        let exp = expectation(description: "Fail immediately on subscription (poisoned publisher)")
        mgr.deviceTokenPub?
            .sink(receiveCompletion: { c in
                print("TEST1: completion = \(c)")
                if case .failure = c { exp.fulfill() }
            }, receiveValue: { v in
                XCTFail("TEST1: Should not receive value in legacy poison mode, got: \(v)")
            })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
        print("TEST1: PASS (legacy poison verified)")
    }

    // MARK: - Test 2: 동일 FCM 토큰 2회 등록 → 내부 device_token 이벤트 중복

    /// PURPOSE:
    /// - 레거시에서는 동일 FCM 토큰이 연속 등록될 때 내부 setDeviceProperties(device_token) 이벤트가
    ///   중복으로 발생하는 문제를 재현합니다.
    ///
    /// LEGACY PASS MEANS:
    /// - 동일 토큰("dup_token")으로 내부 이벤트가 2회 이상 관측됨 → 중복 전송 문제 입증.
    ///
    /// IF FAILS:
    /// - 테스트가 메인 인스턴스를 사용하지 않거나, 충분한 비동기 대기시간이 부족하거나,
    ///   legacy 스위치가 꺼져 있을 가능성.
    func test_Legacy_FCM_DuplicateDeviceTokenEvent() {
        print("TEST2: observe duplicate internal device_token events in legacy mode")

        let token = "dup_token"
        var observed = 0
        let exp = expectation(description: "Observe duplicated device_token events (>= 2)")
        exp.expectedFulfillmentCount = 2

        // 내부 이벤트(payload)가 생성되는 지점을 직접 구독
        notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { payload in
                if let json = payload.records.first?.data {
                    print("TEST2: internal payload = \(json)")
                    if json.contains("\"device_token\":\"\(token)\"") {
                        observed += 1
                        exp.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        // 동일 토큰 2회 등록(legacy 모드에서는 중복 이벤트가 발생해야 함)
        mgr.registerFCMToken(token: token)
        mgr.registerFCMToken(token: token)

        wait(for: [exp], timeout: 2.0)
        print("TEST2: observed duplicates = \(observed)")
        XCTAssertGreaterThanOrEqual(observed, 2, "레거시에서는 중복 이벤트가 발생해야 함")
        print("TEST2: PASS (legacy duplicate internal events verified)")
    }

    // MARK: - Test 3: APNs 최대 재시도 초과 → promise/timeout 정리 미흡

    /// PURPOSE:
    /// - 레거시에서는 APNs 최대 재시도 초과 시 deviceTokenPromise/timeout이 즉시 정리되지 않아
    ///   지연 타임아웃 발화나 중복 완료 레이스 위험이 존재함을 재현합니다.
    ///
    /// LEGACY PASS MEANS:
    /// - apnsState == .failed 이면서, promise/timeout 둘 다 정리되지 않음(nil 아님).
    ///
    /// IF FAILS:
    /// - 레거시 스위치 미적용 또는 코드가 핫픽스 동작으로 정리되었을 가능성.
    func test_Legacy_APNs_MaxRetry_NoCleanup() {
        print("TEST3: simulate APNs max-retry exceeded (legacy no-cleanup)")

        mgr.test_simulateAPNsMaxRetryExceeded()

        let state = mgr.test_getAPNsState()
        let isPromiseNil = mgr.test_isDeviceTokenPromiseNil()
        let isTimeoutNil = mgr.test_isTimeoutWorkItemNil()

        print("TEST3: apnsState=\(state), promiseNil=\(isPromiseNil), timeoutNil=\(isTimeoutNil)")

        XCTAssertEqual(state, .failed, "APNs state should be .failed in legacy")
        XCTAssertFalse(isPromiseNil, "레거시: promise가 정리되지 않음(잠재 레이스)")
        XCTAssertFalse(isTimeoutNil, "레거시: timeout이 남아 중복 완료 위험")
        print("TEST3: PASS (legacy no-cleanup verified)")
    }
}
