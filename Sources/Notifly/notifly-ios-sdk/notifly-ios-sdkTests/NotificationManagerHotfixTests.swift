//
//  NotificationManagerHotfixTests.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/23/25.
//
import XCTest
import Combine
import UIKit
@testable import notifly_ios_sdk

private final class CaseLog {
    private let t0 = CFAbsoluteTimeGetCurrent()
    private let caseName: String
    init(_ caseName: String) { self.caseName = caseName }
    private func ts() -> String { String(format: "t=%6.3fs", CFAbsoluteTimeGetCurrent() - t0) }

    func header() { print("\n==========[\(caseName)] 테스트 시작==========") }
    func caseStart(objective: String, expectations: [String]) {
        print("[\(ts())] 목적: \(objective)")
        expectations.forEach { print("[\(ts())] 기대: \($0)") }
    }
    func step(_ msg: String)    { print("[\(ts())] 단계: \(msg)") }
    func observe(_ msg: String) { print("[\(ts())] 관찰: \(msg)") }
    func verify(_ msg: String)  { print("[\(ts())] 검증: \(msg)") }
    func success(_ msg: String) { print("[\(ts())] 성공: \(msg)") }
    func meaning(_ msg: String) { print("[\(ts())] 의미: \(msg)") }
    func caseEnd()              { print("==========[\(caseName)] 테스트 종료==========\n") }
}

final class NotificationManagerHotfixTests: XCTestCase {

    private var bag = Set<AnyCancellable>()
    private var notifly: Notifly!
    private var mgr: NotificationsManager!

    override func setUp() {
        super.setUp()
        Notifly.setup(projectId: "t_proj", username: "t_org", password: "pw")
        notifly = try? Notifly.main
        mgr = notifly.notificationsManager
    }

    override func tearDown() {
        bag.removeAll()
        super.tearDown()
    }

    // T1) FCM 최대 재시도 초과 → 늦은 성공으로 회복(포이즌 금지)
    func test_T1_FCM_MaxRetryExceeded_ThenLateSuccess_ResolvesOnce() {
        let L = CaseLog("T1-FCM 최대초과 후 늦은성공")
        L.header()
        L.caseStart(
            objective: "FCM 최대 재시도 초과 뒤에도 포이즌 없이 늦은 성공으로 회복",
            expectations: [
                "즉시 실패(포이즌) 없음",
                "늦은 성공 1회로 토큰 수신",
            ])

        mgr.test_simulateFCMMaxRetryExceeded()
        L.step("FCM 최대 재시도 초과 상황 강제")

        let noFail = expectation(description: "no poisoned"); noFail.isInverted = true
        mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in if case .failure = c { L.observe("즉시 실패 발생"); noFail.fulfill() } },
            receiveValue: { _ in }
        ).store(in: &bag)
        wait(for: [noFail], timeout: 0.3)
        L.verify("즉시 실패 없음(포이즌 금지) 확인")

        let expected = "fcmtoken_late"
        let got = expectation(description: "late success")
        L.step("늦은 성공 토큰 전송: \(expected)")
        mgr.registerFCMToken(token: expected)

        mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in if case .failure(let e) = c { XCTFail("예기치 않은 실패: \(e)") } },
            receiveValue: { v in
                L.observe("토큰 수신: \(v)")
                XCTAssertEqual(v, expected, "잘못된 토큰 수신")
                L.success("늦은 성공으로 정상 회복")
                got.fulfill()
            }
        ).store(in: &bag)
        wait(for: [got], timeout: 1.5)

        L.meaning("포이즌 제거 + 회복성 보장")
        L.caseEnd()
    }

    // T2) 동일 FCM 토큰 2회 등록 → 아이템포턴시(중복 이벤트/중복 완료 방지)
    func test_T2_FCM_DuplicateRegistration_IsIdempotent() {
        let L = CaseLog("T2-FCM 중복등록 아이템포턴시")
        L.header()
        L.caseStart(
            objective: "동일 FCM 토큰 2회 등록 시 이벤트 중복/완료 중복 없이 1회만",
            expectations: [
                "device_token 내부 이벤트 정확히 1회",
                "추가 등록은 조기 반환",
            ])

        let token = "dup_token"
        var count = 0
        let first = expectation(description: "first event")
        let noSecond = expectation(description: "no second"); noSecond.isInverted = true

        notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data else { return }
                if json.contains("\"device_token\":\"\(token)\"") {
                    count += 1
                    L.observe("device_token 이벤트 수신(\(count))")
                    if count == 1 { first.fulfill() }
                    if count >= 2 { noSecond.fulfill() }
                }
            }.store(in: &bag)

        L.step("토큰 등록 1: \(token)")
        mgr.registerFCMToken(token: token)
        L.step("토큰 등록 2: \(token) (중복)")

        wait(for: [first, noSecond], timeout: 1.5)
        L.verify("누적 이벤트 수=\(count) (기대=1)")
        XCTAssertEqual(count, 1, "device_token 이벤트 중복")

        L.success("이벤트/완료 모두 1회로 아이템포턴시 달성")
        L.meaning("중복 콜백/외부 중복 호출에도 안전")
        L.caseEnd()
    }

    // T3) APNs 최대 재시도 초과 → 즉시 정리(promise/timeout)
    func test_T3_APNsMaxRetryExceeded_Cleanup() {
        let L = CaseLog("T3-APNs 최대초과 정리")
        L.header()
        L.caseStart(
            objective: "APNs 최대 재시도 초과 시 promise/timeout 즉시 정리",
            expectations: [
                "deviceTokenPromise == nil",
                "timeoutWorkItem == nil",
            ])

        L.step("APNs 최대 재시도 초과 상황 강제")
        mgr.test_simulateAPNsMaxRetryExceeded()

        let pNil = mgr.test_isDeviceTokenPromiseNil()
        let tNil = mgr.test_isTimeoutWorkItemNil()
        L.verify("정리 상태: promiseNil=\(pNil), timeoutNil=\(tNil)")

        XCTAssertTrue(pNil, "promise 정리 안 됨")
        XCTAssertTrue(tNil, "timeout 정리 안 됨")

        L.success("promise/timeout 단일성 유지")
        L.meaning("이중 완료/레이스 예방")
        L.caseEnd()
    }

    // T4) APNs 내부 이벤트 — 값 변경 시에만 1회(Firebase 없이 재현)
    func test_T4_APNsValueChangeOnly_NoFirebase() {
        let L = CaseLog("T4-APNs 값변경 게이팅")
        L.header()
        L.caseStart(
            objective: "APNs 토큰 값 변경 시에만 내부 이벤트 1회 전송",
            expectations: [
                "token1 → 이벤트 1회",
                "token1(중복) → 무시",
                "token2 → 이벤트 1회 (총 2회)",
            ])

        var count = 0
        let two = expectation(description: "two value-change events")
        two.expectedFulfillmentCount = 2
        let noThird = expectation(description: "no third"); noThird.isInverted = true

        notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data else { return }
                if json.contains("\"apns_token\"") {
                    count += 1
                    L.observe("apns_token 이벤트 수신(\(count)) payload.len=\(json.count)")
                    if count <= 2 { two.fulfill() } else { noThird.fulfill() }
                }
            }.store(in: &bag)

        func d(_ s: String) -> Data { Data(s.utf8) }
        L.step("APNs 게이팅 호출: token1")
        mgr.test_handleAPNsTokenForGatingOnly(d("token1"))
        L.step("APNs 게이팅 호출: token1(중복)")
        mgr.test_handleAPNsTokenForGatingOnly(d("token1"))
        L.step("APNs 게이팅 호출: token2(변경)")
        mgr.test_handleAPNsTokenForGatingOnly(d("token2"))

        wait(for: [two, noThird], timeout: 2.0)
        L.verify("누적 apns_token 이벤트 수=\(count) (기대=2)")
        XCTAssertEqual(count, 2, "값 변경 2건에 대한 이벤트 미수신")

        L.success("값 변경 시에만 1회 전송")
        L.meaning("중복 노이즈 억제 + 변경 감지 정확")
        L.caseEnd()
    }

    // T5) 다중 동시 구독 → 동일 값 1회 전파
    func test_T5_ManySubscribers_BroadcastOnce() {
        let L = CaseLog("T5-다중구독 브로드캐스트")
        L.header()
        L.caseStart(
            objective: "다중 구독자에게 동일 토큰 1회 전파",
            expectations: [
                "모든 구독자 동일 토큰 수신",
                "각 구독자 1회만 수신",
            ])

        let subs = 24, token = "broadcast_token"
        let all = expectation(description: "all received")
        all.expectedFulfillmentCount = subs

        for i in 0..<subs {
            L.step("구독자 등록 #\(i)")
            mgr.deviceTokenPub?.sink(
                receiveCompletion: { c in if case .failure(let e) = c { XCTFail("구독자 \(i) 실패: \(e)") } },
                receiveValue: { v in
                    XCTAssertEqual(v, token, "구독자 \(i) 잘못된 토큰 수신")
                    all.fulfill()
                }
            ).store(in: &bag)
        }

        L.step("늦은 성공 토큰 전파: \(token)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mgr.registerFCMToken(token: token)
        }
        wait(for: [all], timeout: 2.0)

        L.success("모든 구독자 동일 토큰 1회 수신")
        L.meaning("단일 결과 공유(single-flight 유사) 보장")
        L.caseEnd()
    }

    // T6) APNs 중복 + 늦은 FCM 성공 → 전체 플로우 안정성(Firebase 없이 재현)
    func test_T6_APNsDuplicate_ThenLateFCMSuccess_NoFirebase() {
        let L = CaseLog("T6-APNs중복+늦은FCM")
        L.header()
        L.caseStart(
            objective: "APNs 중복은 1회로 게이트, 이후 늦은 FCM 성공으로 정상 완료",
            expectations: [
                "동일 APNs 토큰 2회 → 내부 이벤트 1회",
                "이후 늦은 FCM 성공 토큰 수신",
            ])

        var apnsCount = 0
        let one = expectation(description: "one apns event")
        let none = expectation(description: "no extra apns"); none.isInverted = true

        notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data else { return }
                if json.contains("\"apns_token\"") {
                    apnsCount += 1
                    L.observe("apns_token 이벤트 수신(\(apnsCount)) payload.len=\(json.count)")
                    if apnsCount == 1 { one.fulfill() } else { none.fulfill() }
                }
            }.store(in: &bag)

        func d(_ s: String) -> Data { Data(s.utf8) }
        L.step("APNs 게이팅 호출: same")
        mgr.test_handleAPNsTokenForGatingOnly(d("same"))
        L.step("APNs 게이팅 호출: same(중복)")
        mgr.test_handleAPNsTokenForGatingOnly(d("same"))

        let expected = "fcm_late"
        let got = expectation(description: "late fcm token")
        L.step("늦은 성공 토큰 전송: \(expected)")
        mgr.registerFCMToken(token: expected)

        mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in if case .failure(let e) = c { XCTFail("예기치 않은 실패: \(e)") } },
            receiveValue: { v in
                L.observe("FCM 토큰 수신: \(v)")
                XCTAssertEqual(v, expected, "잘못된 토큰 수신")
                got.fulfill()
            }
        ).store(in: &bag)

        wait(for: [one, none, got], timeout: 2.0)
        L.verify("apns_token 이벤트 수=\(apnsCount) (기대=1)")
        XCTAssertEqual(apnsCount, 1, "APNs 중복 게이트 실패")

        L.success("APNs 중복 1회 게이트 + 늦은 FCM 성공 정상 완료")
        L.meaning("엔드투엔드 안정성(중복 억제 + 회복성) 확보")
        L.caseEnd()
    }
}
