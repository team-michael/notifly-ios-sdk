//
//  NotificationManagerHotfixTests.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/26/25.
//
import XCTest
import Combine
import UIKit
@testable import notifly_ios_sdk

// 케이스 로거(결론 규칙: 실패 → 실패원인만, 성공 → 성공/의미만)
private final class CaseLog {
    private let t0 = CFAbsoluteTimeGetCurrent()
    private let caseName: String
    private var didFail = false
    init(_ caseName: String) { self.caseName = caseName }
    private func ts() -> String { String(format: "t=%6.3fs", CFAbsoluteTimeGetCurrent() - t0) }

    func header()               { print("\n==========[\(caseName)] 테스트 시작==========") }
    func caseStart(objective: String, expectations: [String]) {
        print("[\(ts())] 목적: \(objective)")
        expectations.forEach { print("[\(ts())] 기대: \($0)") }
    }
    func step(_ msg: String)    { print("[\(ts())] 단계: \(msg)") }
    func observe(_ msg: String) { print("[\(ts())] 관찰: \(msg)") }
    func verify(_ msg: String)  { print("[\(ts())] 검증: \(msg)") }
    func cause(_ msg: String)   { didFail = true; print("[\(ts())] 실패원인: \(msg)") }
    func success(_ msg: String) { if !didFail { print("[\(ts())] 성공: \(msg)") } }
    func meaning(_ msg: String) { if !didFail { print("[\(ts())] 의미: \(msg)") } }
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
    override func tearDown() { bag.removeAll(); super.tearDown() }

    // APNs JSON에서 apns_token 값(16진 문자열) 추출
    private func extractAPNsToken(from json: String) -> String? {
        guard let r1 = json.range(of: "\"apns_token\":\"") else { return nil }
        let s1 = json[r1.upperBound...]
        guard let r2 = s1.firstIndex(of: "\"") else { return nil }
        return String(s1[..<r2])
    }
    // "token1" 원문을 APNs 토큰 16진 문자열로 예상 변환(테스트 비교용)
    private func expectedHex(_ raw: String) -> String {
        raw.data(using: .utf8, allowLossyConversion: false)!
            .map { String(format: "%02.2hhx", $0) }
            .joined()
    }

    // T1) 기존 구독자 회복 여부 재현:
    // - 레거시: 최대초과 직후 구독 → 즉시 실패(포이즌). 이어서 늦은 성공을 보내도 “같은 구독”은 회복되지 않음
    // - 핫픽스: 최대초과 후 구독해도 즉시 실패 없음. 늦은 성공을 보내면 “같은 구독”이 값 수신
    func test_T1_ExistingSubscriber_Recoverability() {
        let L = CaseLog("T1-기존구독 회복여부"); L.header()
        L.caseStart(
            objective: "FCM 최대초과 후 기존 구독 회복 가능성 비교(레거시: 비회복, 핫픽스: 회복)",
            expectations: [
                "레거시: 기존 구독 즉시 실패(포이즌) → 늦은 성공 후에도 미수신",
                "핫픽스: 기존 구독 즉시 실패 없음 → 늦은 성공 후 기존 구독 수신"
            ])

        // 1) 최대 재시도 초과(레거시: Fail 고정; 핫픽스: 포이즌 없음)
        mgr.test_simulateFCMMaxRetryExceeded()
        L.step("FCM 최대 재시도 초과 강제")

        // 2) 기존 구독(최대초과 ‘이후’ 구독) 생성
        var poisoned = false
        var origReceived = false
        let noPoison = expectation(description: "no_poison"); noPoison.isInverted = true
        let origReceiveExp = expectation(description: "orig_receive")
        origReceiveExp.isInverted = true // 기본은 미수신(레거시) 가정. 핫픽스 흐름에서만 뒤에서 true로 바꿔줌

        var origSink: AnyCancellable?
        origSink = mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in
                if case .failure = c {
                    poisoned = true
                    origSink?.cancel()
                    noPoison.fulfill()
                    L.observe("기존 구독: 즉시 실패 관찰(포이즌)")
                }
            },
            receiveValue: { v in
                origReceived = true
                L.observe("기존 구독: 토큰 수신 \(v)")
                origReceiveExp.fulfill()
            }
        )

        wait(for: [noPoison], timeout: 0.2) // 포이즌 여부 도출
        L.verify("포이즌 여부 = \(poisoned)")

        // 3) 늦은 성공 전송
        let late = "late_token_existing_sub"
        L.step("늦은 성공 토큰 전송(같은 구독 관찰): \(late)")
        if !poisoned {
            // 핫픽스 경로: 기존 구독이 값을 받아야 하므로 invert 해제
            origReceiveExp.isInverted = false
        }
        mgr.registerFCMToken(token: late)

        // 4) 관찰/결론
        wait(for: [origReceiveExp], timeout: 1.0)
        if poisoned {
            // 레거시: 기존 구독 비회복 재현
            if origReceived == false {
                L.cause("""
                기존 구독은 포이즌으로 종료되어, 늦은 성공 이후에도 미수신(회복 불가).
                원인: createTrackingRecord는 실행 시점에 deviceTokenPub을 구독 → Fail 스트림으로 즉시 종료.
                이후 registerFCMToken은 deviceTokenPub을 Just(token)으로 교체하지만 이는 ‘새 구독’에만 반영되어 기존 구독은 복구되지 않음.
                결과: 시점 의존 이벤트 드랍/불안정 및 동일 promise 이중 완료 위험
                """)
            } else {
                L.cause("포이즌 상태에서 기존 구독이 값을 수신. 구현/환경 편차로 레이스가 발생 중(잠재적 이중 완료/불안정 위험)")
            }
        } else {
            // 핫픽스: 기존 구독 회복
            L.success("기존 구독이 늦은 성공을 정상 수신(포이즌 없고 단일 promise/타이머 유지)")
            L.meaning("기존 흐름의 연속성 보장. Fail 고정 제거로 기존 구독이 살아 있어 늦은 성공 수신(퍼블리셔 교체/새 구독 없이 회복). 레거시에선 이 시나리오에서 기존 구독이 포이즌되어 이벤트 드랍 발생")
        }
        L.caseEnd()
    }

    // T2) 동일 FCM 토큰 2회 등록 → 아이템포턴시 + (실패 재현) 중복 이벤트 유도
    func test_T2_FCM_DuplicateRegistration_IsIdempotent() {
        let L = CaseLog("T2-FCM 중복등록 아이템포턴시"); L.header()
        L.caseStart(
            objective: "동일 토큰 2회 등록 시 이벤트/완료 모두 1회",
            expectations: ["device_token 이벤트 정확히 1회", "추가 등록 조기 반환"])

        let token = "dup_token"
        var count = 0
        let first = expectation(description: "first")
        let noSecond = expectation(description: "nosecond"); noSecond.isInverted = true
        var noSecondSignaled = false
        var dupSink: AnyCancellable?

        dupSink = notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data else { return }
                if json.contains("\"device_token\":\"\(token)\"") {
                    count += 1; L.observe("device_token 이벤트(\(count))")
                    if count == 1 { first.fulfill() }
                    if count >= 2, !noSecondSignaled {
                        noSecondSignaled = true
                        dupSink?.cancel()
                        L.cause("""
                        동일 토큰 기반 내부 이벤트가 2회 이상 발생.
                        원인: 동일 FCM 토큰의 반복 등록/콜백 재발행에서 아이템포턴시 가드의 부재 or 미작동.
                        결과: 중복 이벤트/완료 전송 → JSON 인코딩/네트워크 부하 급증, 데이터 왜곡 위험
                        """)
                        noSecond.fulfill()
                    }
                }
            }

        L.step("토큰 등록 1: \(token)")
        mgr.registerFCMToken(token: token)
        L.step("토큰 등록 2(중복): \(token)")
        mgr.registerFCMToken(token: token)

        wait(for: [first, noSecond], timeout: 1.5)
        if count == 1 {
            L.success("이벤트/완료 모두 1회(아이템포턴시) 유지")
            L.meaning("중복 등록/콜백에도 내부 이벤트가 1회로 수렴 → 불필요 부하/중복 처리 억제")
        }
        L.caseEnd()
    }

    // T3) APNs 최대 초과 → 정리 + (필수) 레이스 유도(늦은 성공 2회 연속)
    func test_T3_APNsMaxRetryExceeded_Cleanup_RaceInduced() {
        let L = CaseLog("T3-APNs 최대초과 정리+레이스"); L.header()
        L.caseStart(
            objective: "APNs 최대 초과 시 즉시 정리, 이어서 늦은 성공 2회 레이스에도 안전",
            expectations: ["promise/timeout 즉시 정리", "늦은 성공 2회 연속에도 이중 완료/크래시 없음"])

        L.step("APNs 최대 재시도 초과 강제")
        mgr.test_simulateAPNsMaxRetryExceeded()

        let pNil = mgr.test_isDeviceTokenPromiseNil()
        let tNil = mgr.test_isTimeoutWorkItemNil()
        L.verify("정리 상태: promiseNil=\(pNil), timeoutNil=\(tNil)")

        // 필수 레이스 유도
        L.step("레이스 유도: 늦은 FCM 성공 2회 전송(late_A, late_B)")
        mgr.registerFCMToken(token: "late_A")
        mgr.registerFCMToken(token: "late_B")

        // 구독으로 ‘단일 완료’ 관찰
        let got = expectation(description: "post_race_value")
        mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in if case .failure(let e) = c { XCTFail("예기치 않은 실패: \(e)") } },
            receiveValue: { v in L.observe("레이스 이후 토큰 수신: \(v)"); got.fulfill() }
        ).store(in: &bag)
        wait(for: [got], timeout: 1.0)

        if !pNil || !tNil {
            L.cause("""
            정리 미흡(promise/timeout 잔존) 상태에서 ‘늦은 성공 2회’가 겹침.
            원인: APNs 최대초과 직후 promise/timeout이 즉시 해제되지 않아 동일 promise에 대해 2회 성공 시도가 가능.
            결과: 이중 완료 시도로 크래시 위험(메인스레드 fatal/메모리 오류)
            """)
        } else {
            L.success("정리 완료 + 레이스에도 단일 완료 보장")
            L.meaning("이중 완료/레이스 제거로 안정성 확보")
        }
        XCTAssertTrue(pNil, "promise 정리 실패"); XCTAssertTrue(tNil, "timeout 정리 실패")
        L.caseEnd()
    }

    // T4) APNs 내부 이벤트 — 값 변경 1회 + (실패 재현) 중복 다회/정확 매칭(16진) + inverted 안전화
    func test_T4_APNsValueChangeOnly_NoFirebase_WithStress() {
        let L = CaseLog("T4-APNs 값변경 게이팅+스트레스"); L.header()
        L.caseStart(
            objective: "APNs 토큰 값 변경 시 1회만 전송(중복/스트레스에도 정확)",
            expectations: ["token1(hex) 1회", "token1(hex) 중복 다회 무시", "token2(hex) 1회"])

        let token1Hex = expectedHex("token1")
        let token2Hex = expectedHex("token2")

        var byToken: [String: Int] = [:]
        let two = expectation(description: "two"); two.expectedFulfillmentCount = 2
        let noThird = expectation(description: "no3"); noThird.isInverted = true
        var noThirdSignaled = false
        var apnsSink: AnyCancellable?

        apnsSink = notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data, json.contains("\"apns_token\"") else { return }
                let val = self.extractAPNsToken(from: json) ?? "unknown"
                byToken[val, default: 0] += 1
                let total = byToken.values.reduce(0, +)
                L.observe("apns_token 이벤트(\(total)) token=\(val)")
                if total <= 2 { two.fulfill() }
                else if !noThirdSignaled {
                    noThirdSignaled = true
                    apnsSink?.cancel()
                    L.cause("""
                    APNs 내부 이벤트가 예상 횟수(2회)를 초과.
                    원인: 동일 값 반복 입력/동시 입력의 타이밍 경합.
                    결과: 중복 내부 이벤트 전송 → 인코딩/CPU 스파이크 및 트래픽 증가
                    """)
                    noThird.fulfill()
                }
            }

        func d(_ s: String) -> Data { Data(s.utf8) }
        L.step("APNs 게이팅: token1")
        mgr.test_handleAPNsTokenForGatingOnly(d("token1"))
        L.step("APNs 게이팅: token1(중복 다회)")
        for _ in 0..<3 { mgr.test_handleAPNsTokenForGatingOnly(d("token1")) }
        L.step("APNs 게이팅: token2(변경)")
        mgr.test_handleAPNsTokenForGatingOnly(d("token2"))

        wait(for: [two, noThird], timeout: 2.0)
        L.verify("분포(hex)=\(byToken)")
        if byToken[token1Hex, default: 0] == 1 && byToken[token2Hex, default: 0] == 1 && byToken.values.reduce(0,+) == 2 {
            L.success("값 변경 시 1회만 전송 유지")
            L.meaning("중복 노이즈 억제 + 변경 감지 정확")
        }
        XCTAssertEqual(byToken[token1Hex, default: 0], 1)
        XCTAssertEqual(byToken[token2Hex, default: 0], 1)
        L.caseEnd()
    }

    // T5) 다중 동시 구독 브로드캐스트 + (실패 재현) 동일 토큰 재전파(inverted 안전화)
    func test_T5_ManySubscribers_BroadcastOnce_WithRepeatSend() {
        let L = CaseLog("T5-다중구독 브로드캐스트+재전파"); L.header()
        L.caseStart(
            objective: "다중 구독자에게 동일 토큰 1회 전파, 재전파에도 추가 수신 없음",
            expectations: ["모든 구독자 동일 토큰 수신", "재전파 시 추가 수신 0"])

        let subs = 24, token = "broadcast_token"
        let all = expectation(description: "all"); all.expectedFulfillmentCount = subs
        for i in 0..<subs {
            L.step("구독자 등록 #\(i)")
            mgr.deviceTokenPub?.sink(
                receiveCompletion: { c in if case .failure(let e) = c { XCTFail("구독자 \(i) 실패: \(e)") } },
                receiveValue: { v in XCTAssertEqual(v, token); all.fulfill() }
            ).store(in: &bag)
        }
        L.step("늦은 성공 1회 전파: \(token)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.mgr.registerFCMToken(token: token) }
        wait(for: [all], timeout: 2.0)

        // 재전파 실패 재현: 동일 토큰 재전파 → 새 구독자에서 추가 수신 감지 시 실패
        var extraReceived = 0
        let noMore = expectation(description: "no_more"); noMore.isInverted = true
        var extraSink: AnyCancellable?
        extraSink = mgr.deviceTokenPub?.sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in
                if extraReceived == 0 {
                    extraReceived += 1
                    extraSink?.cancel()
                    L.cause("""
                    동일 토큰 재전파에서 추가 수신 발생.
                    원인: 단일 결과 공유(replay) 불일치 또는 퍼블리셔 재교체로 재방출.
                    결과: 구독자 중복 수신 → 로직 중복 실행/부하 증가
                    """)
                    noMore.fulfill()
                }
            }
        )
        L.step("동일 토큰 재전파: \(token)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.mgr.registerFCMToken(token: token) }
        wait(for: [noMore], timeout: 0.5)

        if extraReceived == 0 {
            L.success("재전파에도 추가 수신 없음")
            L.meaning("단일 결과 공유(replay) 일관 보장")
        }
        XCTAssertEqual(extraReceived, 0, "재전파 추가 수신 발생")
        L.caseEnd()
    }

    // T6) APNs 중복 + 늦은 FCM 성공 E2E + (실패 재현) APNs 동시 중복(inverted 안전화)
    func test_T6_APNsDuplicate_ThenLateFCMSuccess_WithConcurrentDup() {
        let L = CaseLog("T6-APNs중복+늦은FCM+동시중복"); L.header()
        L.caseStart(
            objective: "APNs 중복은 1회로 게이트, 이후 늦은 FCM 성공 정상 완료",
            expectations: ["동일 APNs 2회(동시에) → 내부 이벤트 1회", "그 후 FCM 늦은 성공 수신"])

        var byToken: [String: Int] = [:]
        let one = expectation(description: "one")
        let none = expectation(description: "noextra"); none.isInverted = true
        var noneSignaled = false
        var apnsSink: AnyCancellable?

        apnsSink = notifly.trackingManager.internalEventRequestPayloadPublisher
            .sink { p in
                guard let json = p.records.first?.data, json.contains("\"apns_token\"") else { return }
                let v = self.extractAPNsToken(from: json) ?? "unknown"
                byToken[v, default: 0] += 1
                let total = byToken.values.reduce(0, +)
                if total == 1 { one.fulfill() }
                if total > 1, !noneSignaled {
                    noneSignaled = true
                    apnsSink?.cancel()
                    L.cause("""
                    동일 APNs 값 동시 입력에서 내부 이벤트가 복수로 발생.
                    원인: 동시 중복 입력에 대한 타이밍 경합.
                    결과: 중복 이벤트 전송 → 인코딩/트래픽 폭증, 상태 불안정
                    """)
                    none.fulfill()
                }
            }

        func d(_ s: String) -> Data { Data(s.utf8) }
        L.step("APNs 게이팅 동시 2회: same, same")
        let q = DispatchQueue(label: "t6.concurrent", attributes: .concurrent)
        q.async { self.mgr.test_handleAPNsTokenForGatingOnly(d("same")) }
        q.async { self.mgr.test_handleAPNsTokenForGatingOnly(d("same")) }

        let expected = "fcm_late"
        let got = expectation(description: "late_fcm")
        L.step("늦은 FCM 성공 전송: \(expected)")
        mgr.registerFCMToken(token: expected)
        mgr.deviceTokenPub?.sink(
            receiveCompletion: { c in if case .failure(let e) = c { XCTFail("예기치 않은 실패: \(e)") } },
            receiveValue: { v in XCTAssertEqual(v, expected); got.fulfill() }
        ).store(in: &bag)

        wait(for: [one, none, got], timeout: 2.0)
        let sameHex = expectedHex("same")
        L.verify("apns 분포(hex)=\(byToken) (기대: \(sameHex)=1)")
        if byToken[sameHex, default: 0] == 1 {
            L.success("APNs 중복 1회 게이트 + 늦은 FCM 성공 정상 완료")
            L.meaning("엔드투엔드 안정성(중복 억제 + 회복성) 확보")
        }
        XCTAssertEqual(byToken[sameHex, default: 0], 1, "APNs 중복 게이트 실패")
        L.caseEnd()
    }
}
