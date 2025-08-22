import Foundation

class NotiflyAsyncWorker {
    private let semaphore: DispatchSemaphore
    private let queue = DispatchQueue(label: "com.notifly.asyncWorkerQueue")
    private var pendingTasks: [(@escaping () -> Void) -> Void] = []
    private var activeUnlockItem: DispatchWorkItem?
    private var activeToken: UInt64 = 0
    private var nextToken: UInt64 = 0
    private var finishRequestToken: UInt64?
    private let timeoutSeconds: TimeInterval = 10

    init(semaphoreValue: Int = 1) {
        semaphore = DispatchSemaphore(value: semaphoreValue)
    }

    // 새 API: 비동기 완료 콜백 기반. 호출부는 작업 완료 시점에 finishTask()를 정확히 1회 호출한다.
    func addTask(lockAcquired: Bool = false,
                 task: @escaping (_ finishTask: @escaping () -> Void) -> Void) {
        if lockAcquired {
            // 상위 컨텍스트가 이미 락을 보유한 경우: 세마포어를 획득하지 않고 실행. finishTask는 no-op.
            queue.async {
                task({})
            }
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            if self.semaphore.wait(timeout: .now()) == .success {
                self.start(task: task)
            } else {
                self.pendingTasks.append(task)
            }
        }
    }

    private func start(task: @escaping (_ finishTask: @escaping () -> Void) -> Void) {
        var timeoutItem: DispatchWorkItem?
        let token = nextToken &+ 1
        nextToken = token

        timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, let item = timeoutItem, !item.isCancelled else { return }
            // 제한 시간 경과 시에도 언락을 보장한다. (토큰 검증 없음: 활성 타임아웃만 activeToken과 일치)
            self.queue.async { [weak self] in
                self?.unlockOnQueue()
            }
        }

        queue.async { [weak self] in
            guard let self = self, let timeoutItem = timeoutItem else { return }
            self.activeToken = token
            self.activeUnlockItem = timeoutItem
            self.queue.asyncAfter(deadline: .now() + self.timeoutSeconds, execute: timeoutItem)
        }

        let finishTask: () -> Void = { [weak self] in
            // 호출부에서 완료 시점에 단 한 번 호출되도록 계약한다. 중복 호출 시 내부적으로 no-op 처리된다.
            guard let self = self else { return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                self.finishRequestToken = token
                self.unlockOnQueue()
            }
        }

        // 태스크는 워커 전용 직렬 큐에서 실행한다.
        queue.async {
            task(finishTask)
        }
    }

    // unlock 단일화: 현재 활성 스케줄만 취소/해제하고, 다음 태스크를 즉시 실행 시도한다.
    private func unlockOnQueue() {
        // 토큰 기반 매칭: finishTask 경로라면 토큰 일치시에만 해제. timeout 경로는 토큰 없음으로 통과
        if let requested = finishRequestToken, requested != activeToken {
            finishRequestToken = nil
            return
        }
        finishRequestToken = nil

        if let active = activeUnlockItem {
            active.cancel()
            activeUnlockItem = nil
            semaphore.signal()
            executeNextTaskIfNeeded()
        }
    }

    // 큐 컨텍스트 강제: 모든 상태 변경은 queue.async 경유로 호출되어야 함
    private func executeNextTaskIfNeeded() {
        if !pendingTasks.isEmpty, semaphore.wait(timeout: .now()) == .success {
            let nextTask = pendingTasks.removeFirst()
            start(task: nextTask)
        }
    }
}
