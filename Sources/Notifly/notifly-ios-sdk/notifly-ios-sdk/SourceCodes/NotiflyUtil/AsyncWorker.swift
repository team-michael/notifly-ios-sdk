import Foundation

class NotiflyAsyncWorker {
    private let semaphore: DispatchSemaphore
    private let queue = DispatchQueue(label: "com.notifly.asyncWorkerQueue")
    private var pendingTasks: [(@escaping () -> Void) -> Void] = []
    private var activeUnlockItem: DispatchWorkItem?
    private var activeToken: UInt64 = 0
    private var nextToken: UInt64 = 0
    private let timeoutSeconds: TimeInterval = 10

    init(semaphoreValue: Int = 1) {
        semaphore = DispatchSemaphore(value: semaphoreValue)
    }

    // 유일한 외부 접근 경로: 비동기 완료 콜백 기반. 호출부는 작업 완료 시점마다 finishTask()를 정확히 1회 호출.
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
        // 임의의 토큰: 스케줄 식별을 위한 증가 값. 오버플로우 되지 않도록 주의.
        let token = nextToken &+ 1
        nextToken = token

        registerUnlockSchedule(token: token)

        // 완료 콜백: 자신의 토큰을 전달하여 토큰 매칭 기반으로만 해제
        let finishTask: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                self.unlockOnQueue(finishToken: token)
            }
        }

        // 태스크 및 세마포어 제어는 워커 전용 직렬 큐에서 실행.
        queue.async {
            task(finishTask)
        }
    }

    private func registerUnlockSchedule(token: UInt64) {
        var timeoutItem: DispatchWorkItem?

        timeoutItem = DispatchWorkItem { [weak self, weak timeoutItem] in
            guard let self = self, let item = timeoutItem, !item.isCancelled else { return }
            // 제한 시간 경과 시에도 언락 보장. timeout 경로는 finishToken=nil로 활성 스케줄 해제.
            self.queue.async { [weak self] in
                self?.unlockOnQueue(finishToken: nil)
            }
        }

        queue.async { [weak self] in
            guard let self = self, let item = timeoutItem else { return }
            self.activeToken = token
            self.activeUnlockItem = item
            self.queue.asyncAfter(deadline: .now() + self.timeoutSeconds, execute: item)
        }
    }

    // unlock 외부 접근 금지: 세마포어 제어는 AsyncWorker 내부에서만 허용
    private func unlockOnQueue(finishToken: UInt64?) {
        // finish 경로: 활성 토큰과 불일치 시 지연/중복 완료 → 무시(no-op)
        if let t = finishToken, t != activeToken {
            return
        }

        if let active = activeUnlockItem {
            active.cancel()
            activeUnlockItem = nil
            semaphore.signal()
            executeNextTaskIfNeeded()
        }
    }

    private func executeNextTaskIfNeeded() {
        if !pendingTasks.isEmpty, semaphore.wait(timeout: .now()) == .success {
            let nextTask = pendingTasks.removeFirst()
            start(task: nextTask)
        }
    }
}
