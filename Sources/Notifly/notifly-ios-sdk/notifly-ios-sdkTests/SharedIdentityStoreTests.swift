import Foundation
import Security
import XCTest
@testable import notifly_ios_sdk

final class SharedIdentityStoreTests: XCTestCase {
    private let worker = NotiflyAsyncWorker()
    private let identity = StoredIdentity(
        projectID: "project-a",
        deviceID: "existing-device",
        externalUserID: "existing-user",
        username: "sdk-user"
    )

    func testMissingItemIsTheOnlySuccessfulNil() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        XCTAssertNil(try load(store).get())
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecNotAvailable] {
            keychain.readStatus = status
            assertError(load(store), .keychain(status))
        }
    }

    func testLockedKeychainDoesNotReturnMissing() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.readStatus = errSecInteractionNotAllowed
        assertError(load(store), .keychain(errSecInteractionNotAllowed))
        keychain.readStatus = nil
        keychain.data = try JSONEncoder().encode(identity)
        XCTAssertEqual(try load(store).get(), identity)
    }

    func testSuccessfulLoadIsCachedUntilExplicitRefresh() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.data = try JSONEncoder().encode(identity)
        XCTAssertEqual(try load(store).get(), identity)
        let loggedOut = StoredIdentity(
            projectID: "project-a",
            deviceID: "existing-device",
            externalUserID: nil,
            username: "sdk-user"
        )
        keychain.data = try JSONEncoder().encode(loggedOut)
        XCTAssertEqual(try load(store).get(), identity)
        XCTAssertEqual(try load(store, forceRefresh: true).get(), loggedOut)
        XCTAssertEqual(try load(store).get(), loggedOut)
    }

    func testFailedRefreshDoesNotLeaveStaleCacheAvailable() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.data = try JSONEncoder().encode(identity)
        _ = try load(store).get()
        keychain.readStatus = errSecInteractionNotAllowed
        assertError(load(store, forceRefresh: true), .keychain(errSecInteractionNotAllowed))
        assertError(load(store), .keychain(errSecInteractionNotAllowed))
    }

    func testSavePreservesFieldsAndSetsSharedDeviceOnlyProtection() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        try save(store, identity).get()
        let stored = try JSONDecoder().decode(StoredIdentity.self, from: XCTUnwrap(keychain.data))
        XCTAssertEqual(stored, identity)
        XCTAssertEqual(
            keychain.attributes[kSecAttrAccessGroup as String] as? String,
            "group.notifly.test"
        )
        XCTAssertEqual(
            keychain.attributes[kSecAttrService as String] as? String,
            "tech.notifly.identity"
        )
        XCTAssertEqual(keychain.attributes[kSecAttrAccount as String] as? String, "project-a")
        XCTAssertEqual(
            keychain.attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(keychain.attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(try load(store).get(), identity)
    }

    func testUpdatePreservesDeviceIDAndPersistsLogout() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        try save(store, identity).get()
        let loggedOut = StoredIdentity(
            projectID: "project-a",
            deviceID: "existing-device",
            externalUserID: nil,
            username: "sdk-user"
        )
        try save(store, loggedOut).get()
        XCTAssertEqual(try load(store, forceRefresh: true).get(), loggedOut)
        XCTAssertEqual(
            try JSONDecoder().decode(StoredIdentity.self, from: XCTUnwrap(keychain.data)),
            loggedOut
        )
    }

    func testFailedWriteDoesNotChangeCache() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        try save(store, identity).get()
        let before = keychain.data
        keychain.writeStatus = errSecInteractionNotAllowed
        let replacement = StoredIdentity(
            projectID: "project-a",
            deviceID: "replacement",
            externalUserID: nil,
            username: "sdk-user"
        )
        assertError(save(store, replacement), .keychain(errSecInteractionNotAllowed))
        XCTAssertEqual(try load(store).get(), identity)
        XCTAssertEqual(keychain.data, before)
    }

    func testFailedFirstSaveDoesNotPublishAttemptedValue() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.writeStatus = errSecMissingEntitlement
        assertError(save(store, identity), .keychain(errSecMissingEntitlement))
        XCTAssertNil(try load(store).get())
        XCTAssertNil(keychain.data)
    }

    func testCorruptRecordIsNotMissingOrOverwritten() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.data = Data("not-json".utf8)
        let before = keychain.data
        assertError(load(store), .invalidData)
        assertError(save(store, identity), .invalidData)
        XCTAssertEqual(keychain.data, before)
    }

    func testFutureSchemaIsPreservedEvenWhenItsFieldsAreUnknown() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.data = Data(#"{"schemaVersion":2,"futureField":"preserve"}"#.utf8)
        let before = keychain.data
        assertIdentityError(load(store), .unsupportedSchema(2))
        assertIdentityError(save(store, identity), .unsupportedSchema(2))
        XCTAssertEqual(keychain.data, before)
    }

    func testForeignProjectRecordCannotBeReadOrOverwritten() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        let foreign = StoredIdentity(
            projectID: "project-b",
            deviceID: "other-device",
            externalUserID: nil,
            username: "other"
        )
        keychain.data = try JSONEncoder().encode(foreign)
        let before = keychain.data
        assertIdentityError(load(store), .projectMismatch)
        assertIdentityError(save(store, identity), .projectMismatch)
        XCTAssertEqual(keychain.data, before)
    }

    func testForeignProjectInputCannotBeSaved() throws {
        let keychain = FakeIdentityKeychain()
        let store = try SharedIdentityStore(
            projectID: "project-b",
            accessGroup: "group.notifly.test",
            keychain: keychain
        )
        assertIdentityError(save(store, identity), .projectMismatch)
        XCTAssertNil(keychain.data)
    }

    func testEmptyConfigurationDoesNotFallBackToDefaultGroup() {
        for (project, group) in [
            ("", "group.notifly.test"), ("project-a", ""), ("project-a", "  "),
        ] {
            XCTAssertThrowsError(try SharedIdentityStore(projectID: project, accessGroup: group)) {
                error in
                XCTAssertEqual(error as? KeychainError, .invalidConfiguration)
            }
        }
    }

    func testWorkerCallerKeepsKeychainOffMainThread() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.onOperation = { XCTAssertFalse(Thread.isMainThread) }
        let done = expectation(description: "save completes on worker")
        worker.addTask { finish in
            defer { finish() }
            do { try store.save(self.identity) } catch { XCTFail("Save failed: \(error)") }
            XCTAssertFalse(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(try load(store, forceRefresh: true).get(), identity)
    }

    func testQueuedOperationsPreserveSaveOrder() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        let done = expectation(description: "all operations finish")
        done.expectedFulfillmentCount = 21
        worker.addTask { finish in
            defer { finish() }
            for index in 0..<20 {
                let value = StoredIdentity(
                    projectID: "project-a", deviceID: "existing-device",
                    externalUserID: "user-\(index)", username: "sdk-user"
                )
                do { try store.save(value) } catch { XCTFail("Save failed: \(error)") }
                done.fulfill()
            }
            do {
                let value = try store.load(forceRefresh: true)
                XCTAssertEqual(value?.externalUserID, "user-19")
            } catch { XCTFail("Load after saves failed: \(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testDuplicateCreationDoesNotOverwriteAnotherWriter() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.writeStatus = errSecDuplicateItem
        assertError(save(store, identity), .keychain(errSecDuplicateItem))
        XCTAssertNil(keychain.data)
    }

    func testLegacyPayloadPreservesSerializedKeysAndDropsPassword() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        keychain.data = Data(
            #"{"schemaVersion":1,"projectId":"project-a","deviceId":"existing-device","externalUserId":"existing-user","username":"sdk-user","password":"legacy"}"#
                .utf8
        )
        XCTAssertEqual(try load(store).get(), identity)
        try save(store, identity).get()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(keychain.data)) as? [String: Any]
        )
        XCTAssertEqual(
            object as NSDictionary,
            [
                "schemaVersion": 1,
                "projectId": "project-a",
                "deviceId": "existing-device",
                "externalUserId": "existing-user",
                "username": "sdk-user",
            ] as NSDictionary
        )
        XCTAssertEqual(try load(store, forceRefresh: true).get(), identity)
    }

    func testSaveRechecksPersistedSchemaEvenAfterCachingSupportedIdentity() throws {
        let keychain = FakeIdentityKeychain()
        let store = try makeStore(keychain)
        try save(store, identity).get()
        keychain.data = Data(#"{"schemaVersion":2,"futureField":"preserve"}"#.utf8)
        let before = keychain.data
        assertIdentityError(save(store, identity), .unsupportedSchema(2))
        XCTAssertEqual(keychain.data, before)
    }

    private func assertIdentityError<T>(
        _ result: Result<T, Error>,
        _ expected: SharedIdentityStoreError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success: XCTFail("Expected identity failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? SharedIdentityStoreError, expected, file: file, line: line)
        }
    }

    private func makeStore(_ keychain: FakeIdentityKeychain) throws -> SharedIdentityStore {
        try SharedIdentityStore(
            projectID: "project-a",
            accessGroup: "group.notifly.test",
            keychain: keychain
        )
    }

    private func load(_ store: SharedIdentityStore, forceRefresh: Bool = false) -> Result<
        StoredIdentity?, Error
    > {
        let done = expectation(description: "load")
        var result: Result<StoredIdentity?, Error> = .failure(KeychainError.invalidData)
        worker.addTask { finish in
            defer { finish() }
            do { result = .success(try store.load(forceRefresh: forceRefresh)) } catch { result = .failure(error) }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        return result
    }

    private func save(_ store: SharedIdentityStore, _ value: StoredIdentity) -> Result<Void, Error>
    {
        let done = expectation(description: "save")
        var result: Result<Void, Error> = .failure(KeychainError.invalidData)
        worker.addTask { finish in
            defer { finish() }
            do { try store.save(value); result = .success(()) } catch { result = .failure(error) }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        return result
    }

    private func assertError<T>(
        _ result: Result<T, Error>,
        _ expected: KeychainError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success: XCTFail("Expected storage failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? KeychainError, expected, file: file, line: line)
        }
    }
}

/// Replaces only Security I/O so lock/entitlement failures are deterministic.
/// Test configuration changes happen between completed operations; worker-owned I/O is serial.
private final class FakeIdentityKeychain: KeychainProcessing, @unchecked Sendable {
    var data: Data?
    var readStatus: OSStatus?
    var writeStatus: OSStatus?
    var attributes: [String: Any] = [:]
    var onOperation: (() -> Void)?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        onOperation?()
        guard validScope(query) else { return (errSecParam, nil) }
        if let status = readStatus { return (status, nil) }
        return data.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        onOperation?()
        guard validScope(query) else { return errSecParam }
        if let status = writeStatus { return status }
        guard data == nil else { return errSecDuplicateItem }
        attributes = query
        data = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        onOperation?()
        guard validScope(query) else { return errSecParam }
        if let status = writeStatus { return status }
        guard data != nil else { return errSecItemNotFound }
        self.attributes.merge(attributes) { _, new in new }
        data = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    private func validScope(_ query: [String: Any]) -> Bool {
        query[kSecClass as String] as? String == kSecClassGenericPassword as String
            && query[kSecAttrAccessGroup as String] as? String == "group.notifly.test"
            && query[kSecAttrService as String] as? String == "tech.notifly.identity"
            && query[kSecAttrAccount as String] as? String == "project-a"
            && query[kSecAttrSynchronizable as String] as? Bool == false
    }
}
