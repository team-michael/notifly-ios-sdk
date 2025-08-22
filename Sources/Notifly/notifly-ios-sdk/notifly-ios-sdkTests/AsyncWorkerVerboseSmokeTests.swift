//
//  AsyncWorkerVerboseSmokeTests.swift
//  notifly-ios-sdk
//
//  Created by 서노리 on 8/22/25.
//
//  목적: NotiflyAsyncWorker의 핵심 보장(동시성 1, FIFO, timeout/late-finish 무시, idempotent,  nested no-deadlock, stress)을
//  외부 의존 없이(토큰/네트워크 X) 순수 로직으로 검증한다. (실제 통신을 통한 테스트가 가장 정확)

import XCTest
@testable import notifly_ios_sdk

// 타임라인 수집 도우미(사람이 읽기 쉬운 로그 + 테스트 첨부)
private final class Timeline {
    // 이벤트 병렬 접근 보호용 직렬 큐
    private let q = DispatchQueue(label: "timeline.queue")
    // 누적 이벤트 문자열
    private var events: [String] = []
    // 기준 시각(상대 시간 로그용)
    private let t0 = CFAbsoluteTimeGetCurrent()

    // 타임라인 로그 남기기(케이스이름, 스텝/메시지)
    func log(_ caseName: String, _ step: String) {
        // 상대 시간 계산
        let dt = CFAbsoluteTimeGetCurrent() - t0
        // 보기 좋은 형식으로 한 줄 생성
        let line = String(format: "[%6.3fs] %-32s | %@", dt, ("[" + caseName + "]") as NSString, step)
        // 내부 큐에서 배열에 추가(스레드 안전)
        q.async { self.events.append(line) }
        // 콘솔에도 바로 출력
        print(line)
    }

    // 현재까지의 타임라인을 테스트 첨부물로 추가
    func attach(to testCase: XCTestCase, name: String) {
        var snap: [String] = []
        // 스냅샷 안전하게 가져오기
        q.sync { snap = events }
        // 줄바꿈으로 합치기
        let text = snap.joined(separator: "\n")
        // Xcode 테스트 첨부물로 추가(Reports > Attachments에서 확인 가능)
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

final class AsyncWorkerEndToEndTests: XCTestCase {

    // MARK: - 01) 활성 동시성 1 보장 (오버랩 없음)
    // 설명: 동시에 여러 태스크를 넣어도 실제 실행(inflight)은 항상 1개여야 한다.
    // 방법: inflight 카운터(max 기록)로 동시 실행 여부 확인.
    func test_01_NoOverlap() {
        // 케이스 식별자(로그용)
        let C = "NoOverlap"
        // 타임라인 인스턴스
        let tl = Timeline()
        // 테스트 대상 워커
        let worker = NotiflyAsyncWorker()
        // inflight/최대값 접근용 락
        let lock = NSLock()

        // 현재 실행 중 태스크 수
        var inflight = 0
        // 실행 중 최대 동시 수(항상 1이어야 함)
        var maxInflight = 0
        // 전체 완료 대기(10개)
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = 10

        // 10개의 태스크 스케줄
        for i in 0..<10 {
            tl.log(C, "schedule T\(i)")
            worker.addTask { finishTask in
                // 시작 시 inflight 증가
                tl.log(C, "start    T\(i)")
                lock.lock(); inflight += 1; maxInflight = max(maxInflight, inflight); lock.unlock()

                // 약간의 지연 후 finishTask 호출(정상 완료)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
                    tl.log(C, "finish   T\(i) (success)")
                    lock.lock(); inflight -= 1; lock.unlock()
                    finishTask()
                    done.fulfill()
                }
            }
        }

        // 전부 완료될 때까지 대기
        wait(for: [done], timeout: 5)
        // 동시성 1 검증
        XCTAssertEqual(maxInflight, 1, "활성 동시성은 항상 1이어야 함")
        // 타임라인 첨부
        tl.attach(to: self, name: C)
    }

    // MARK: - 02) 선입선출(FIFO) 시작 순서(연속 add 시)
    // 설명: 연속적으로 addTask 호출 시 시작 순서는 FIFO가 되어야 한다(공정성 강화 구현 검증).
    // 방법: 0,1,2 순서로 스케줄/시작 로그 확인.
    func test_02_FIFOStartOrder_ForSequentialAdds() {
        let C = "FIFOStartOrder"
        let tl = Timeline()
        let worker = NotiflyAsyncWorker()
        // 3개 완료 대기
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = 3

        // 0,1,2 순서로 스케줄
        for i in 0..<3 {
            tl.log(C, "schedule T\(i)")
            worker.addTask { finishTask in
                // 시작 순서 확인용 로그
                tl.log(C, "start    T\(i)")
                // i에 따라 다른 지연 후 완료(완료 순서는 달라도 허용)
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.01) {
                    tl.log(C, "finish   T\(i) (success)")
                    finishTask()
                    done.fulfill()
                }
            }
        }

        // 완료 대기
        wait(for: [done], timeout: 3)
        // 타임라인 첨부(FIFO 시작 순서 확인은 로그 시각적으로 점검)
        tl.attach(to: self, name: C)
    }

    // MARK: - 03) 타임아웃 후 늦은 finishTask는 무시(토큰 가드)
    // 설명: timeout으로 이미 다음 작업이 진행된 후, 이전 작업의 늦은 finish가 와도 무시되어야 한다.
    // 방법: T0는 finishTask 미호출 → timeout 유도, 이후 T1/T2 정상 흐름, 마지막에 T0의 늦은 finish 호출(no-op).
    func test_03_TimeoutThenLateFinish_Ignored() {
        let C = "TimeoutThenLateFinish"
        let tl = Timeline()
        let worker = NotiflyAsyncWorker()

        // 테스트 기준 상수(프로덕션 워커의 기본 timeout과 동일)
        let TIMEOUT: TimeInterval = 10.0
        // 타임스탬프 기록용
        var t0Start: CFAbsoluteTime?
        var t1Start: CFAbsoluteTime?

        // 늦은 finish 호출 저장
        var lateFinish: (() -> Void)?

        // [스텝] T0 예약 (finishTask 미호출로 timeout 유도)
        tl.log(C, "schedule T0 (will timeout)")
        worker.addTask { finishTask in
            t0Start = CFAbsoluteTimeGetCurrent()
            tl.log(C, "start    T0")
            // finishTask() 호출하지 않음 → TIMEOUT 후 워커 내부 timeout으로 해제
            lateFinish = finishTask
        }

        // [스텝] T1 예약 (T0 timeout 이후에 시작해야 함)
        let t1 = expectation(description: "T1")
        tl.log(C, "schedule T1")
        worker.addTask { finishTask in
            t1Start = CFAbsoluteTimeGetCurrent()
            tl.log(C, "start    T1")
            // 정상 완료
            finishTask()
            tl.log(C, "finish   T1 (success)")
            t1.fulfill()
        }

        // [정보 로그] T0 timeout 예상 시각에 맞춰 타임라인에 표시(내부 timeout과 거의 일치)
        if let t0Start = t0Start {
            let dt = t0Start + TIMEOUT - CFAbsoluteTimeGetCurrent()
            if dt > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + dt) {
                    tl.log(C, "timeout  T0 fired (expected ~\(Int(TIMEOUT))s)")
                }
            }
        } else {
            // T0 start 로그 직후에 등록될 수 있도록 아주 짧게 지연하여 표시
            DispatchQueue.global().asyncAfter(deadline: .now() + TIMEOUT) {
                tl.log(C, "timeout  T0 fired (expected ~\(Int(TIMEOUT))s)")
            }
        }

        // [검증] T1이 TIMEOUT 이후에 시작했는지(여유 0.5s) 확인
        wait(for: [t1], timeout: TIMEOUT + 2.0)
        if let t0 = t0Start, let t1s = t1Start {
            let diff = t1s - t0
            XCTAssertGreaterThanOrEqual(diff, TIMEOUT - 0.5,
                                        "T1 must start after T0 timeout (diff=\(diff)s)")
        } else {
            XCTFail("Missing start timestamps for T0/T1")
        }

        // [스텝] T2 예약 (T0 timeout 이후 파이프라인 정상 동작 확인)
        let t2 = expectation(description: "T2")
        tl.log(C, "schedule T2")
        worker.addTask { finishTask in
            tl.log(C, "start    T2 (should run after T0 timeout)")
            finishTask()
            tl.log(C, "finish   T2 (success)")
            t2.fulfill()
        }
        wait(for: [t2], timeout: 3.0)

        // [스텝] T0의 늦은 finish 호출 → 토큰 불일치로 무시되어야 함(no-op)
        tl.log(C, "call     T0 late finishTask() (should be ignored)")
        lateFinish?()

        // [스텝] sentinel 예약: 비정상 추가 실행 없이 정상 진행 가능한지 확인
        let s = expectation(description: "sentinel")
        tl.log(C, "schedule sentinel")
        worker.addTask { finishTask in
            tl.log(C, "start    sentinel")
            finishTask()
            tl.log(C, "finish   sentinel (success)")
            s.fulfill()
        }
        wait(for: [s], timeout: 3.0)

        // 타임라인 첨부(콘솔 출력과 함께 리포트에도 저장)
        tl.attach(to: self, name: C)
    }

    // MARK: - 04) finishTask 이중 호출은 idempotent
    // 설명: 같은 태스크에서 finishTask를 두 번 이상 호출해도 실제 해제는 한 번만 수행되어야 한다.
    // 방법: A에서 finish 2회 호출, B가 정확히 1번만 실행되는지 확인.
    func test_04_DoubleFinish_Idempotent() {
        let C = "DoubleFinish"
        let tl = Timeline()
        let worker = NotiflyAsyncWorker()

        // A 스케줄
        tl.log(C, "schedule A")
        worker.addTask { finishTask in
            // A 시작
            tl.log(C, "start    A")
            // 첫 번째 finish(유효)
            finishTask()
            tl.log(C, "finish   A (finish#1)")
            // 두 번째 finish(무시되어야 함)
            finishTask()
            tl.log(C, "finish   A (finish#2 - ignored)")
        }

        // B: 정확히 한 번만 실행되어야 함
        let tB = expectation(description: "B")
        var ranB = 0

        // B 스케줄
        tl.log(C, "schedule B")
        worker.addTask { finishTask in
            // B 시작
            tl.log(C, "start    B")
            // B 실행 횟수 카운트(1이어야 함)
            ranB += 1
            // B 정상 완료
            finishTask()
            tl.log(C, "finish   B (success)")
            tB.fulfill()
        }

        // B 완료 대기
        wait(for: [tB], timeout: 3)
        // B가 딱 한 번만 실행되었는지 검증
        XCTAssertEqual(ranB, 1)
        // 타임라인 첨부
        tl.attach(to: self, name: C)
    }

    // MARK: - 05) lockAcquired=true 중첩 호출(no-op) 데드락 없음
    // 설명: 부모 태스크(lockAcquired=false) 안에서 자식 태스크(lockAcquired=true)를 실행해도
    //       자식의 finishTask는 no-op 계약이며, 데드락 없이 정상 종료되어야 한다.
    // 방법: Outer(락 보유) → Inner(락 미획득/no-op) → Outer 정상 finish.
    func test_05_Nested_LockAcquiredTrue_NoDeadlock() {
        let C = "NestedLockAcquired"
        let tl = Timeline()
        let worker = NotiflyAsyncWorker()
        // 전체 완료 대기
        let done = expectation(description: "done")

        // Outer: lockAcquired=false(세마포어 획득)
        tl.log(C, "schedule Outer(lockAcquired=false)")
        worker.addTask(lockAcquired: false) { outerFinish in
            tl.log(C, "start    Outer")
            // Inner: lockAcquired=true(세마포어 미획득, finishTask는 no-op)
            tl.log(C, "schedule Inner(lockAcquired=true)")
            worker.addTask(lockAcquired: true) { innerFinish in
                tl.log(C, "start    Inner")
                // no-op 호출(부모의 언락에 의존)
                innerFinish()
                tl.log(C, "finish   Inner (no-op)")
            }
            // 부모 락 정상 해제
            outerFinish()
            tl.log(C, "finish   Outer (success)")
            // 케이스 종료
            done.fulfill()
        }

        // 완료 대기
        wait(for: [done], timeout: 3)
        // 타임라인 첨부
        tl.attach(to: self, name: C)
    }

    // MARK: - 06) 스트레스(랜덤 지연, 다량 태스크)
    // 설명: 다량(50개) 태스크를 랜덤 지연으로 실행해도 동시성 1/FIFO/정상 완료 흐름이 유지되어야 한다.
    // 방법: 랜덤 딜레이로 finishTask 호출, 전부 완료할 때까지 대기 + 타임라인 확인.
    func test_06_Stress_RandomDurations() {
        let C = "Stress"
        let tl = Timeline()
        let worker = NotiflyAsyncWorker()
        // 태스크 수
        let N = 50
        // N개 완료 대기
        let done = expectation(description: "done")
        done.expectedFulfillmentCount = N

        // 0..<(N) 반복
        for i in 0..<N {
            // 스케줄 로그
            tl.log(C, "schedule T\(i)")
            // 랜덤 지연(0~20ms)
            let delay = Double.random(in: 0...0.02)
            // 태스크 추가
            worker.addTask { finishTask in
                // 시작 로그
                tl.log(C, "start    T\(i)")
                // 랜덤 지연 후 finishTask 호출
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    tl.log(C, "finish   T\(i) (success)")
                    finishTask()
                    done.fulfill()
                }
            }
        }

        // 전체 완료 대기(타임아웃 10초)
        wait(for: [done], timeout: 10)
        // 타임라인 첨부
        tl.attach(to: self, name: C)
    }
}
