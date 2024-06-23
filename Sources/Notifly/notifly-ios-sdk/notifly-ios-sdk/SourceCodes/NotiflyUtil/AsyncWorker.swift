import Foundation

class NotiflyAsyncWorker {
    private let semaphore: DispatchSemaphore
    private var pendingTasks: [() -> Void] = []
    private let queue = DispatchQueue(label: "com.notifly.asyncWorkerQueue")

    init(semaphoreValue: Int = 1) {
        semaphore = DispatchSemaphore(value: semaphoreValue)
    }

    private func performAsyncTask(task: @escaping () -> Void) {
        queue.async {
            task()
        }
    }

    private func executePendingTask() {
        queue.async {
            if let nextTask = self.pendingTasks.first {
                if self.semaphore.wait(timeout: .now()) == .success {
                    self.pendingTasks.removeFirst()
                    self.performAsyncTask(task: nextTask)
                }
            }
        }
    }

    func addTask(lockAcquired: Bool = false, task: @escaping () -> Void) {
        if lockAcquired {
            queue.async {
                self.performAsyncTask(task: task)
            }
            return
        }

        if semaphore.wait(timeout: .now()) == .success {
            performAsyncTask(task: task)
        } else {
            queue.async {
                self.pendingTasks.append(task)
            }
        }
    }

    func unlock() {
        semaphore.signal()
        executePendingTask()
    }
}
