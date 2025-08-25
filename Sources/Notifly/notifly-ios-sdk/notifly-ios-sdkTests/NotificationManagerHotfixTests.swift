//
//  Untitled.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/23/25.
//
import XCTest
import Combine
@testable import notifly_ios_sdk

final class NotificationsManagerHotfixTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        // Notifly.main 접근 경로가 내부에서 사용되므로 더미로 세팅
        // FirebaseApp 초기화가 없어도 setup()은 가볍게 진행됩니다.
        Notifly.setup(projectId: "test_project", username: "test_org", password: "pwd")
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // 1) FCM 최대 재시도 초과 후에도 퍼블리셔가 독(poison) 상태가 아니고,
    //    늦게 도착한 성공 콜백으로 정상 회복되는지 확인
    func test_FCM_MaxRetryExceeded_ThenLateSuccess_PublisherResolves() {
        let mgr = NotificationsManager()

        // 최대 재시도 초과 상황 시뮬레이션(핫픽스 경로)
        mgr.test_simulateFCMMaxRetryExceeded()
        XCTAssertEqual(mgr.test_getFCMState(), .failed)

        // 늦게 도착한 성공 콜백 시뮬레이션
        let expected = "fcmtoken_1"
        mgr.registerFCMToken(token: expected)

        // 이후 퍼블리셔에서 정상 토큰 수신
        let exp = expectation(description: "Receive token after late success")
        mgr.deviceTokenPub?
            .sink(receiveCompletion: { completion in
                if case .failure(let err) = completion {
                    XCTFail("Unexpected failure: \(err)")
                }
            }, receiveValue: { token in
                XCTAssertEqual(token, expected)
                exp.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(mgr.test_getLastFCMToken(), expected)
    }

    // 2) 동일 FCM 토큰이 중복으로 들어와도 재진입/이중 완료가 발생하지 않는지 확인
    func test_FCM_DuplicateRegistration_NoDoubleCompletion() {
        let mgr = NotificationsManager()

        let token = "fcmtoken_dup"
        mgr.registerFCMToken(token: token)

        // 최초 완료 후 promise는 nil로 정리되어야 함
        XCTAssertTrue(mgr.test_isDeviceTokenPromiseNil())

        // 동일 토큰 재등록 → 조기 반환(아무 일도 일어나지 않아야 함)
        mgr.registerFCMToken(token: token)

        // 여전히 promise는 nil, 마지막 토큰은 동일
        XCTAssertTrue(mgr.test_isDeviceTokenPromiseNil())
        XCTAssertEqual(mgr.test_getLastFCMToken(), token)
        XCTAssertEqual(mgr.test_getFCMState(), .success)
    }

    // 3) APNs 최대 재시도 초과 시 promise 1회 실패 + 정리(타임아웃 취소) 보장
    func test_APNs_MaxRetryExceeded_CleansPromiseAndTimeout() {
        let mgr = NotificationsManager()

        // 초기화 시 deviceTokenPromise/timeout이 세팅됨
        // 최대 재시도 초과 시뮬레이션 → 정리 경로 진입
        mgr.test_simulateAPNsMaxRetryExceeded()

        XCTAssertEqual(mgr.test_getAPNsState(), .failed)
        XCTAssertTrue(mgr.test_isDeviceTokenPromiseNil(), "promise must be nil after clean-up")
        XCTAssertTrue(mgr.test_isTimeoutWorkItemNil(), "timeout must be cancelled and nil")
    }

    // 4) 실패 이후에도 퍼블리셔가 poison되지 않고, 후속 성공으로 회복 가능한지 재확인
    func test_Publisher_NotPoisoned_AfterFailures() {
        let mgr = NotificationsManager()

        // FCM 실패 경로를 먼저 밟음(최대 재시도 초과)
        mgr.test_simulateFCMMaxRetryExceeded()
        XCTAssertEqual(mgr.test_getFCMState(), .failed)

        // 그 뒤 성공
        let expected = "fcmtoken_2"
        mgr.registerFCMToken(token: expected)

        // 새 구독자 관점에서 정상 값 재생산되는지 확인
        let exp = expectation(description: "Receive token after recovery")
        mgr.deviceTokenPub?
            .sink(receiveCompletion: { completion in
                if case .failure(let err) = completion {
                    XCTFail("Unexpected failure: \(err)")
                }
            }, receiveValue: { token in
                XCTAssertEqual(token, expected)
                exp.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }
}
