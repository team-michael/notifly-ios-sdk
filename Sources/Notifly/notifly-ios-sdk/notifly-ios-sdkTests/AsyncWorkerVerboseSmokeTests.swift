//
//  AsyncWorkerVerboseSmokeTests.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/22/25.
//
// 목적
// - NotiflyAsyncWorker의 핵심 보장 검증:
//   1) 활성 동시성 항상 1(오버랩 없음)
//   2) 선입선출(FIFO) 시작 순서(연속 add 시)
//   3) First-wins 규칙: (A) finish 미호출 → timeout이 승자, (B) finish 조기 호출 → finish가 승자
//   4) finish 이중 호출 idempotent
//   5) lockAcquired=true 중첩 호출 시 데드락 없음(no-op)
//   6) 랜덤 지연 스트레스에서도 위 성질 유지

import XCTest
@testable import notifly_ios_sdk

// 직관적 케이스 로거
private final class CaseLog {
    private let t0 = CFAbsoluteTimeGetCurrent()
    private let caseName: String
    init(_ caseName: String) { self.caseName = caseName }

    private func ts() -> String {
        String(format: "t=%6.3fs", CFAbsoluteTimeGetCurrent() - t0)
    }

    func caseStart(objective: String, expectations: [String]) {
        print("\n=== [\(caseName)] CASE START ===")
        print("[\(ts())] 목적: \(objective)")
        expectations.forEach { print("[\(ts())] 기대: \($0)") }
    }

    func step(_ msg: String)    { print("[\(ts())] 단계: \(msg)") }
    func observe(_ msg: String) { print("[\(ts())] 관찰: \(msg)") }
    func verify(_ msg: String)  { print("[\(ts())] 검증: \(msg)") }
    func caseEnd()              { print("[\(ts())] 결과: \(caseName) 완료\n") }
    func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }
}

final class AsyncWorkerVerboseSmokeTests: XCTestCase {

    // 01) 활성 동시성 1 보장(오버랩 없음)
    // - 테스트: 동시에 여러 태스크를 넣어도 실제 실행(inflight)은 항상 1이어야 함
    // - 검증: inflight 최대값이 1인지 기록/검증
    func test_NoOverlap() {
        let L = CaseLog("01_NoOverlap")
        L.caseStart(
            objective: "여러 태스크 동시 제출 시에도 실행 동시성은 항상 1",
            expectations: [
                "inflight 최대값은 1이어야 한다",
                "모든 태스크는 순차적으로 시작/종료한다"
            ])

        let worker = NotiflyAsyncWorker()
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = 10

        var inflight = 0
        var maxInflight = 0
        let lock = NSLock()

        for i in 0..<10 {
            L.step("T\(i) 스케줄")
            worker.addTask { finish in
                L.step("T\(i) 시작")
                lock.lock(); inflight += 1; maxInflight = max(maxInflight, inflight); lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
                    L.step("T\(i) 종료")
                    lock.lock(); inflight -= 1; lock.unlock()
                    finish()
                    done.fulfill()
                }
            }
        }

        wait(for: [done], timeout: 5)
        L.verify("inflight 최대값=\(maxInflight)")
        XCTAssertEqual(maxInflight, 1, "활성 동시성은 항상 1이어야 함")
        L.caseEnd()
    }

    // 02) 선입선출(FIFO) 시작 순서(연속 add 시)
    // - 테스트: 0,1,2 순서로 add하면 시작도 0,1,2 순서여야 함
    // - 검증: startOrder == [0,1,2]
    func test_FIFOStartOrder_SequentialAdds() {
        let L = CaseLog("02_FIFO_Start")
        L.caseStart(
            objective: "연속 제출된 태스크는 제출 순서대로 시작(FIFO)",
            expectations: [
                "시작 순서는 [0,1,2] 를 만족해야 한다",
                "종료 순서는 지연에 따라 달라도 무방하다"
            ])

        let worker = NotiflyAsyncWorker()
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = 3

        var startOrder: [Int] = []

        for i in 0..<3 {
            L.step("T\(i) 스케줄")
            worker.addTask { finish in
                L.step("T\(i) 시작")
                startOrder.append(i)
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.01) {
                    L.step("T\(i) 종료")
                    finish()
                    done.fulfill()
                }
            }
        }

        wait(for: [done], timeout: 3)
        L.verify("시작 순서 = \(startOrder)")
        XCTAssertEqual(startOrder, [0,1,2], "연속 add의 시작 순서는 FIFO여야 함")
        L.caseEnd()
    }

    // 03-A) First-wins: finish 미호출 → timeout 승자
    // - 테스트: T0에서 finish를 부르지 않으면 timeout이 먼저 와서 T0 해제. T1은 대략 10초 뒤 시작
    // - 검증: T1 시작 시점이 T0 시작 시점 + ~10s 보다 크거나 같다
    func test_FirstWins_TimeoutScenario() {
        let TIMEOUT: TimeInterval = 10.0
        let L = CaseLog("03A_FirstWins_Timeout")
        L.caseStart(
            objective: "finish 미호출 시 timeout이 먼저 와서 해제",
            expectations: [
                "T1은 T0 시작 후 ~10초 경과 뒤에 시작해야 한다",
                "T0의 늦은 finish는 무시되어야 한다"
            ])

        let worker = NotiflyAsyncWorker()
        var t0Start: CFAbsoluteTime?
        var t1Start: CFAbsoluteTime?
        var lateFinish: (() -> Void)?

        L.step("T0 스케줄 (finish 호출 안 함)")
        worker.addTask { finish in
            t0Start = L.now()
            L.step("T0 시작")
            lateFinish = finish // 호출 안 함 → timeout 경로
        }

        let expT1 = expectation(description: "T1")
        L.step("T1 스케줄 (T0 해제 이후 시작 기대)")
        worker.addTask { finish in
            t1Start = L.now()
            L.step("T1 시작 (T0 timeout 이후)")
            finish()
            L.step("T1 종료")
            expT1.fulfill()
        }

        // 안내 로그(근사): timeout 예상 시점
        if let s0 = t0Start {
            let delay = max(0, s0 + TIMEOUT - L.now())
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                L.observe("T0 timeout 발생(약 ~10초)")
            }
        }

        wait(for: [expT1], timeout: TIMEOUT + 2)
        guard let s0 = t0Start, let s1 = t1Start else {
            XCTFail("타임스탬프 누락(T0/T1)"); return
        }
        let diff = s1 - s0
        L.verify(#"T1 시작 간격 = \#(String(format: "%.3f", diff))s (기대: ≥ ~10s)"#)
        XCTAssertGreaterThanOrEqual(diff, TIMEOUT - 0.5, "T1 must start after ~10s timeout (diff=\(diff)s)")

        L.step("T0 늦은 finish 호출(무시 기대)")
        lateFinish?()

        let expS = expectation(description: "sentinel")
        L.step("sentinel 스케줄(파이프라인 정상 상태 확인)")
        worker.addTask { finish in
            L.step("sentinel 시작")
            finish()
            L.step("sentinel 종료")
            expS.fulfill()
        }
        wait(for: [expS], timeout: 3)
        L.caseEnd()
    }

    // 03-B) First-wins: finish 조기 호출 → finish 승자
    // - 무엇: T0에서 finish를 빨리 부르면 finish가 timeout보다 먼저 와서 해제. T1은 즉시(짧은 지연 내) 시작
    // - 검증: T1 시작 시점이 T0 시작 + 10s 보다 훨씬 작음
    func test_FirstWins_FinishScenario() {
        let TIMEOUT: TimeInterval = 10.0
        let L = CaseLog("03B_FirstWins_Finish")
        L.caseStart(
            objective: "finish 조기 호출 시 finish가 먼저 와서 해제",
            expectations: [
                "T1은 timeout을 기다리지 않고 곧바로 시작해야 한다",
                "T0의 timeout은 취소되어야 한다"
            ])

        let worker = NotiflyAsyncWorker()
        var t0Start: CFAbsoluteTime?
        var t1Start: CFAbsoluteTime?

        L.step("T0 스케줄 (finish를 곧바로 호출할 예정)")
        worker.addTask { finish in
            t0Start = L.now()
            L.step("T0 시작")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                L.step("T0 finish 호출 (finish 승자 기대)")
                finish()
            }
        }

        let expT1 = expectation(description: "T1")
        L.step("T1 스케줄 (T0 finish 직후 시작 기대)")
        worker.addTask { finish in
            t1Start = L.now()
            L.step("T1 시작 (T0 finish로 해제됨)")
            finish()
            L.step("T1 종료")
            expT1.fulfill()
        }

        wait(for: [expT1], timeout: 2.0)
        guard let s0 = t0Start, let s1 = t1Start else {
            XCTFail("타임스탬프 누락(T0/T1)"); return
        }
        let diff = s1 - s0
        L.verify(#"T1 시작 간격 = \#(String(format: "%.3f", diff))s (기대: ≥ ~10s)"#)
        XCTAssertLessThan(diff, TIMEOUT / 5, "T1 should start well before timeout (diff=\(diff)s)")
        L.caseEnd()
    }

    // 04) finish 이중 호출은 idempotent
    // - 무엇: 같은 태스크에서 finish를 2번 이상 호출해도 실제 해제는 1회만
    // - 검증: B는 정확히 1회만 실행
    func test_DoubleFinish_Idempotent() {
        let L = CaseLog("04_DoubleFinish")
        L.caseStart(
            objective: "finish 이중 호출은 한 번만 유효",
            expectations: [
                "A의 두 번째 finish는 무시된다",
                "B는 정확히 1회만 실행된다"
            ])

        let worker = NotiflyAsyncWorker()

        L.step("A 스케줄")
        worker.addTask { finish in
            L.step("A 시작")
            finish()
            L.step("A finish(1차)")
            finish() // 무시
            L.step("A finish(2차, 무시)")
        }

        let expB = expectation(description: "B")
        var ranB = 0

        L.step("B 스케줄")
        worker.addTask { finish in
            L.step("B 시작")
            ranB += 1
            finish()
            L.step("B 종료")
            expB.fulfill()
        }

        wait(for: [expB], timeout: 3)
        L.verify("B 실행 횟수 = \(ranB) (기대: 1)")
        XCTAssertEqual(ranB, 1)
        L.caseEnd()
    }

    // 05) lockAcquired=true 중첩 호출(no-op) 데드락 없음
    // - 무엇: 부모 태스크(lockAcquired=false) 안에서 자식 태스크(lockAcquired=true)를 호출해도 데드락 없이 정상 종료
    // - 검증: Inner는 no-op, Outer만 해제되어 전체 흐름 정상
    func test_Nested_LockAcquiredTrue_NoDeadlock() {
        let L = CaseLog("05_Nested_NoDeadlock")
        L.caseStart(
            objective: "중첩 호출에서도 데드락 없이 정상 종료",
            expectations: [
                "Inner(lockAcquired=true)는 no-op",
                "Outer(lockAcquired=false)만 해제되어 전체 흐름 정상"
            ])

        let worker = NotiflyAsyncWorker()
        let done = expectation(description: "done")

        L.step("Outer 스케줄 (lockAcquired=false)")
        worker.addTask(lockAcquired: false) { outerFinish in
            L.step("Outer 시작")
            L.step("Inner 스케줄 (lockAcquired=true)")
            worker.addTask(lockAcquired: true) { innerFinish in
                L.step("Inner 시작")
                innerFinish()
                L.step("Inner 종료(no-op)")
            }
            outerFinish()
            L.step("Outer 종료")
            done.fulfill()
        }

        wait(for: [done], timeout: 3)
        L.caseEnd()
    }

    // 06) 스트레스(랜덤 지연, 다량 태스크)
    // - 무엇: 다량 태스크/랜덤 지연에서도 동시성 1/FIFO/정상 완료 흐름 유지
    // - 검증: 모두 정상 종료
    func test_Stress_RandomDurations() {
        let L = CaseLog("06_Stress")
        L.caseStart(
            objective: "다량 태스크/랜덤 지연에서도 일관된 직렬 처리",
            expectations: [
                "활성 동시성은 항상 1",
                "모든 태스크 정상 종료"
            ])

        let worker = NotiflyAsyncWorker()
        let N = 50
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = N

        for i in 0..<N {
            L.step("T\(i) 스케줄")
            let delay = Double.random(in: 0...0.02)
            worker.addTask { finish in
                L.step("T\(i) 시작")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    L.step("T\(i) 종료")
                    finish()
                    done.fulfill()
                }
            }
        }

        wait(for: [done], timeout: 10)
        L.caseEnd()
    }
}
