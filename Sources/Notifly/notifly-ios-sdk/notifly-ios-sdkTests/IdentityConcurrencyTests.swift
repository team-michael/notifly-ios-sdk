import Foundation
import Security
import XCTest
@testable import notifly_ios_sdk

final class IdentityConcurrencyTests: XCTestCase {
    private let identity = StoredIdentity(
        projectID: "concurrency-test", deviceID: "existing-device",
        externalUserID: "before", username: "sdk-user"
    )

    func testConcurrentDirectLoadsShareOneKeychainRead() throws {
        let backend = try ControlledIdentityKeychain(identity)
        let store = try makeStore(backend)
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            XCTAssertEqual(try? store.load(), self.identity)
        }
        XCTAssertEqual(backend.readCount, 1)
        XCTAssertEqual(store.current, identity)
    }

    func testDirectWriteCannotOvertakeAnInFlightRead() throws {
        let backend = try ControlledIdentityKeychain(identity)
        let gate = ReadGate(entered: expectation(description: "read is paused"))
        backend.firstReadGate = gate
        let store = try makeStore(backend)
        let loaded = expectation(description: "first read finishes")
        let written = expectation(description: "write follows read")
        DispatchQueue.global().async {
            XCTAssertEqual(try? store.load(), self.identity)
            loaded.fulfill()
        }
        wait(for: [gate.entered], timeout: 3)
        let updated = StoredIdentity(
            projectID: identity.projectID, deviceID: identity.deviceID,
            externalUserID: "after", username: identity.username
        )
        let earlyWrite = expectation(description: "no write while the read is blocked")
        earlyWrite.isInverted = true
        let attempted = expectation(description: "independent writer started")
        DispatchQueue.global().async {
            attempted.fulfill()
            do { try store.save(updated) } catch { XCTFail("Save failed: \(error)") }
            if !gate.isReleased { earlyWrite.fulfill() }
            written.fulfill()
        }
        wait(for: [attempted], timeout: 3)
        wait(for: [earlyWrite], timeout: 0.1)
        gate.release()
        wait(for: [loaded, written], timeout: 3)
        XCTAssertEqual(store.current, updated)
        XCTAssertEqual(try backend.persisted(), updated)
        XCTAssertEqual(backend.maximumConcurrentOperations, 1)
    }

    func testNetworkCallbackCanPersistBeforeFinishingTheWorkerTask() throws {
        let backend = try ControlledIdentityKeychain(identity)
        let store = try makeStore(backend)
        let worker = NotiflyAsyncWorker()
        let done = expectation(description: "next task sees the response identity")
        worker.addTask { finish in
            DispatchQueue.global().async {
                do { try store.setExternalUserID("from-response") } catch {
                    XCTFail("Cannot apply response: \(error)")
                }
                finish()
            }
        }
        worker.addTask { finish in
            XCTAssertEqual(store.current?.externalUserID, "from-response")
            XCTAssertEqual(try? backend.persisted().deviceID, "existing-device")
            finish()
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    private func makeStore(_ backend: ControlledIdentityKeychain) throws -> SharedIdentityStore {
        try SharedIdentityStore(
            projectID: identity.projectID, accessGroup: "group.notifly.test", keychain: backend
        )
    }
}

/// A bounded blocking Security call, controlled without blocking the test's main thread.
private final class ReadGate: @unchecked Sendable {
    let entered: XCTestExpectation
    private let condition = NSCondition()
    private var isOpen = false

    init(entered: XCTestExpectation) { self.entered = entered }

    func wait() {
        entered.fulfill()
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(3)
        while !isOpen {
            guard condition.wait(until: deadline) else {
                XCTFail("Test did not release the Keychain read")
                return
            }
        }
    }

    var isReleased: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isOpen
    }

    func release() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

/// All mutable fields are locked. The gate is configured before tasks are created.
private final class ControlledIdentityKeychain: KeychainProcessing, @unchecked Sendable {
    var firstReadGate: ReadGate?
    private let lock = NSLock()
    private var data: Data
    private var reads = 0
    private var writes = 0
    private var active = 0
    private var maximum = 0

    init(_ identity: StoredIdentity) throws { data = try JSONEncoder().encode(identity) }

    var readCount: Int { withLock { reads } }
    var writeCount: Int { withLock { writes } }
    var maximumConcurrentOperations: Int { withLock { maximum } }

    func persisted() throws -> StoredIdentity {
        try JSONDecoder().decode(StoredIdentity.self, from: withLock { data })
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        beginOperation()
        defer { endOperation() }
        let record: (Data, ReadGate?) = withLock {
            reads += 1
            return (data, reads == 1 ? firstReadGate : nil)
        }
        record.1?.wait()
        return (errSecSuccess, record.0)
    }

    func add(_ query: [String: Any]) -> OSStatus { errSecDuplicateItem }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        beginOperation()
        defer { endOperation() }
        guard let value = attributes[kSecValueData as String] as? Data else { return errSecParam }
        withLock { data = value; writes += 1 }
        return errSecSuccess
    }

    private func beginOperation() {
        withLock { active += 1; maximum = max(maximum, active) }
    }

    private func endOperation() { withLock { active -= 1 } }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
