import Foundation

class NotiflyAsyncWorker {
    private let semaphore: DispatchSemaphore
    private var pendingTasks: [() -> Void] = []
    private let queue = DispatchQueue(label: "com.notifly.asyncWorkerQueue")
    private var unlockSchedules: [DispatchWorkItem] = []

    init(semaphoreValue: Int = 1) {
        semaphore = DispatchSemaphore(value: semaphoreValue)
    }

    private func performAsyncTask(task: @escaping () -> Void) {
        queue.async {
            task()
        }
    }

    private func executeNextTaskIfNeeded() {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            if !self.pendingTasks.isEmpty,
               let nextTask = self.pendingTasks.first
            {
                if self.semaphore.wait(timeout: .now()) == .success {
                    self.registerUnlockSchedule()
                    self.pendingTasks.removeFirst()
                    self.performAsyncTask(task: nextTask)
                }
            }
        }
    }

    func addTask(lockAcquired: Bool = false, task: @escaping () -> Void) {
        if lockAcquired {
            queue.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.performAsyncTask(task: task)
            }
            return
        }

        if semaphore.wait(timeout: .now()) == .success {
            registerUnlockSchedule()
            performAsyncTask(task: task)
        } else {
            queue.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.pendingTasks.append(task)
            }
        }
    }

    func unlock() {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            if !self.unlockSchedules.isEmpty,
               let unlockSchedule = self.unlockSchedules.first
            {
                unlockSchedule.cancel()
                self.unlockSchedules.removeFirst()
                semaphore.signal()
                executeNextTaskIfNeeded()
            }
        }
    }

    private func registerUnlockSchedule() {
        let timeoutTask = DispatchWorkItem {
            self.unlock()
        }
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.unlockSchedules.append(timeoutTask)
            self.queue.asyncAfter(deadline: .now() + 10, execute: timeoutTask)
        }
    }
}
