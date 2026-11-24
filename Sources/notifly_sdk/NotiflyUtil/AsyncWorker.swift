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

    // The task entry point uses completion callbacks. Each caller must call finishTask() exactly once.
    func addTask(
        lockAcquired: Bool = false,
        task: @escaping (_ finishTask: @escaping () -> Void) -> Void
    ) {
        if lockAcquired {
            // If the caller already owns the lock, skip acquiring the semaphore and provide a no-op completion.
            queue.async {
                task({})
            }
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            if semaphore.wait(timeout: .now()) == .success {
                start(task: task)
            }
            else {
                pendingTasks.append(task)
            }
        }
    }

    private func start(task: @escaping (_ finishTask: @escaping () -> Void) -> Void) {
        // Advance the task identifier using wrapping arithmetic.
        let token = nextToken &+ 1
        nextToken = token

        registerUnlockSchedule(token: token)

        // Pass the task token to release only the matching active task.
        let finishTask: () -> Void = { [weak self] in
            guard let self = self else { return }
            queue.async { [weak self] in
                guard let self = self else { return }
                unlockOnQueue(finishToken: token)
            }
        }

        // Manage tasks and the semaphore on the worker serial queue.
        queue.async {
            task(finishTask)
        }
    }

    private func registerUnlockSchedule(token: UInt64) {
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Release on timeout as well; a nil finishToken releases the active task.
            queue.async { [weak self] in
                guard let self = self else { return }
                unlockOnQueue(finishToken: nil)
            }
        }

        activeToken = token
        activeUnlockItem = timeoutItem
        queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)
    }

    // Keep semaphore release private to the worker.
    private func unlockOnQueue(finishToken: UInt64?) {
        // Ignore delayed or duplicate completions whose token does not match the active task.
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
