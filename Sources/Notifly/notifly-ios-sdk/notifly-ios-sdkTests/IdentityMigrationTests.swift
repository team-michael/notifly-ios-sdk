import Foundation
import Security
import XCTest
@testable import notifly_ios_sdk

final class IdentityMigrationTests: XCTestCase {
    private let worker = NotiflyAsyncWorker()
    private var defaults: UserDefaults?
    private let backend = MigrationMemoryKeychain()
    private let projectID = "migration-project"
    private var generationCount = 0

    override func setUpWithError() throws {
        let suite = "tech.notifly.migration-tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    func testMigrationPreservesRawIdentifiersAndRemovesOnlyIdentityKeys() throws {
        try seed(deviceID: "Original-ID_대소문자", userID: "유저-A")
        let defaults = try XCTUnwrap(defaults)
        defaults.set("password", forKey: key(NotiflyCustomDefaultKey.password))
        defaults.set("jwt", forKey: key(NotiflyCustomDefaultKey.authToken))
        defaults.set("registered", forKey: key(NotiflyCustomDefaultKey.alreadyRegistered))
        defaults.set("other-device", forKey: "other_\(NotiflyCustomDefaultKey.deviceId)")
        let store = try makeStore()
        XCTAssertNil(store.current)
        let migrated = try load(store).get()
        XCTAssertEqual(migrated.deviceID, "Original-ID_대소문자")
        XCTAssertEqual(migrated.externalUserID, "유저-A")
        XCTAssertEqual(try persisted(), migrated)
        XCTAssertEqual(store.current, migrated)
        for name in identityKeys { XCTAssertNil(defaults.object(forKey: key(name))) }
        XCTAssertEqual(defaults.string(forKey: key(NotiflyCustomDefaultKey.password)), "password")
        XCTAssertEqual(defaults.string(forKey: key(NotiflyCustomDefaultKey.authToken)), "jwt")
        XCTAssertEqual(
            defaults.string(forKey: key(NotiflyCustomDefaultKey.alreadyRegistered)),
            "registered"
        )
        XCTAssertEqual(
            defaults.string(forKey: "other_\(NotiflyCustomDefaultKey.deviceId)"),
            "other-device"
        )
        XCTAssertEqual(generationCount, 0)
    }

    func testUserDefaultsDeviceTakesPrecedenceOverOldPrivateKeychain() throws {
        try seed()
        backend.legacyData = Data("different-private-id".utf8)
        XCTAssertEqual(try load(makeStore()).get().deviceID, "existing-device")
        XCTAssertEqual(backend.legacyReads, 0)
        XCTAssertEqual(backend.legacyData, Data("different-private-id".utf8))
    }

    func testOldPrivateKeychainIsIgnoredWhenDefaultsDeviceIsAbsent() throws {
        try seed(deviceID: nil)
        backend.legacyData = Data("old-private-id".utf8)
        let identity = try load(makeStore()).get()
        XCTAssertEqual(identity.deviceID, "generated-device")
        XCTAssertEqual(identity.externalUserID, "existing-user")
        XCTAssertEqual(generationCount, 1)
        XCTAssertEqual(backend.legacyReads, 0)
        XCTAssertEqual(backend.legacyData, Data("old-private-id".utf8))
        XCTAssertEqual(try persisted(), identity)
    }

    func testFreshInstallGeneratesWhenSharedKeychainAndDefaultsAreAbsent() throws {
        let identity = try load(makeStore()).get()
        XCTAssertEqual(identity.deviceID, "generated-device")
        XCTAssertNil(identity.externalUserID)
        XCTAssertEqual(backend.legacyReads, 0)
        XCTAssertEqual(generationCount, 1)
        XCTAssertEqual(try persisted(), identity)
    }

    func testLockedOrUnentitledSharedKeychainDoesNotDeleteOrGenerate() throws {
        try seed()
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecNotAvailable] {
            backend.readStatus = status
            let store = try makeStore()
            assertFailure(load(store), KeychainError.keychain(status))
            XCTAssertNil(store.current)
            XCTAssertEqual(try legacyDevice(), "existing-device")
        }
        XCTAssertEqual(generationCount, 0)
        XCTAssertEqual(backend.writes, 0)
    }

    func testCorruptAndFutureSharedPayloadsAreNotOverwritten() throws {
        try seed()
        for data in [Data("invalid".utf8), Data(#"{"schemaVersion":99}"#.utf8)] {
            backend.sharedData = data
            guard case .failure = load(try makeStore()) else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(backend.sharedData, data)
            XCTAssertEqual(try legacyDevice(), "existing-device")
        }
    }

    func testMalformedLegacyValueIsPreserved() throws {
        try seed()
        try XCTUnwrap(defaults).set(42, forKey: key(NotiflyCustomDefaultKey.deviceId))
        assertFailure(load(try makeStore()), IdentityMigrationError.invalidLegacyValue)
        XCTAssertEqual(
            try XCTUnwrap(defaults).integer(forKey: key(NotiflyCustomDefaultKey.deviceId)),
            42
        )
        XCTAssertNil(backend.sharedData)
    }

    func testFailedWriteLeavesLegacyAndMemoryUntouched() throws {
        try seed()
        backend.writeStatus = errSecNotAvailable
        let store = try makeStore()
        assertFailure(load(store), KeychainError.keychain(errSecNotAvailable))
        XCTAssertEqual(try legacyDevice(), "existing-device")
        XCTAssertNil(store.current)
        XCTAssertNil(backend.sharedData)
    }

    func testReadbackFailureKeepsLegacyAndRestartResumesCleanup() throws {
        try seed()
        backend.afterWrite = { self.backend.readStatus = errSecInteractionNotAllowed }
        let store = try makeStore()
        assertFailure(load(store), KeychainError.keychain(errSecInteractionNotAllowed))
        XCTAssertEqual(try legacyDevice(), "existing-device")
        XCTAssertNil(store.current)
        backend.readStatus = nil
        backend.afterWrite = nil
        let restarted = try load(makeStore()).get()
        XCTAssertEqual(restarted.deviceID, "existing-device")
        XCTAssertEqual(backend.writes, 1)
        XCTAssertNil(try legacyDevice())
    }

    func testMismatchedReadbackDoesNotDeleteLegacy() throws {
        try seed()
        let replacement = try JSONEncoder().encode(identity(deviceID: "other"))
        backend.afterWrite = { self.backend.sharedData = replacement }
        assertFailure(load(try makeStore()), IdentityMigrationError.verificationFailed)
        XCTAssertEqual(try legacyDevice(), "existing-device")
    }

    func testInterruptedPartialCleanupCanBeRepeated() throws {
        try seed()
        backend.sharedData = try JSONEncoder().encode(identity())
        try XCTUnwrap(defaults).removeObject(forKey: key(NotiflyCustomDefaultKey.deviceId))
        XCTAssertEqual(try load(makeStore()).get(), identity())
        XCTAssertEqual(try load(makeStore()).get(), identity())
        XCTAssertEqual(backend.writes, 0)
    }

    func testConflictingExistingIdentityIsNotOverwrittenOrDeleted() throws {
        try seed()
        backend.sharedData = try JSONEncoder().encode(identity(deviceID: "other"))
        let before = backend.sharedData
        assertFailure(load(try makeStore()), IdentityMigrationError.conflictingIdentity)
        XCTAssertEqual(backend.sharedData, before)
        XCTAssertEqual(try legacyDevice(), "existing-device")
    }

    func testLegacyChangeDuringCopyIsPreserved() throws {
        try seed()
        let defaults = try XCTUnwrap(defaults)
        backend.afterWrite = {
            defaults.set("new-user", forKey: self.key(NotiflyCustomDefaultKey.externalUserId))
        }
        assertFailure(load(try makeStore()), IdentityMigrationError.legacyChanged)
        XCTAssertEqual(
            defaults.string(forKey: key(NotiflyCustomDefaultKey.externalUserId)),
            "new-user"
        )
        XCTAssertEqual(try legacyDevice(), "existing-device")
    }

    func testConcurrentCreatorCannotBeOverwritten() throws {
        try seed()
        let winner = try JSONEncoder().encode(identity(deviceID: "winner"))
        backend.beforeInsert = { self.backend.sharedData = winner }
        assertFailure(load(try makeStore()), IdentityMigrationError.verificationFailed)
        XCTAssertEqual(backend.sharedData, winner)
        XCTAssertEqual(try legacyDevice(), "existing-device")
    }

    func testConcurrentLoadsCreateOnlyOneRecord() throws {
        try seed()
        let store = try makeStore()
        let done = expectation(description: "all loads")
        done.expectedFulfillmentCount = 10
        for _ in 0..<10 {
            worker.addTask { finish in
                defer { finish() }
                do { _ = try store.load() } catch { XCTFail("Load failed: \(error)") }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(backend.writes, 1)
    }

}

extension IdentityMigrationTests {
    func testExtensionBeforeAppUpgradeReadsLegacyWithoutWritingOrDeleting() throws {
        try seed()
        XCTAssertEqual(try load(makeStore(readOnly: true)).get(), identity())
        XCTAssertEqual(backend.writes, 0)
        XCTAssertEqual(try legacyDevice(), "existing-device")
    }

    func testExtensionNeverGeneratesOrUsesItsPrivateDeviceID() throws {
        backend.legacyData = Data("extension-private-id".utf8)
        assertFailure(
            load(try makeStore(readOnly: true)),
            IdentityMigrationError.identityUnavailable
        )
        XCTAssertEqual(generationCount, 0)
        XCTAssertEqual(backend.legacyReads, 0)
    }

    func testExtensionRefreshObservesLogoutFromApp() throws {
        try seed()
        let app = try makeStore()
        _ = try load(app).get()
        let extensionStore = try makeStore(readOnly: true)
        XCTAssertEqual(try load(extensionStore).get().externalUserID, "existing-user")
        try update(app, userID: nil).get()
        XCTAssertNil(try load(extensionStore, refresh: true).get().externalUserID)
        XCTAssertEqual(try load(makeStore()).get().deviceID, "existing-device")
    }

    func testFailedUserSwitchPreservesOldPersistentAndInMemoryIdentity() throws {
        try seed()
        let store = try makeStore()
        _ = try load(store).get()
        backend.writeStatus = errSecNotAvailable
        assertFailure(update(store, userID: "next"), KeychainError.keychain(errSecNotAvailable))
        XCTAssertEqual(store.current, identity())
        XCTAssertEqual(try persisted(), identity())
    }

    func testQueuedUserSwitchAndLogoutPersistInOrder() throws {
        try seed()
        let store = try makeStore()
        _ = try load(store).get()
        let done = expectation(description: "ordered user changes")
        done.expectedFulfillmentCount = 3
        worker.addTask { finish in
            defer { finish() }
            for userID in ["next", "last", nil] {
                do { try store.setExternalUserID(userID) } catch { XCTFail("Write failed: \(error)") }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 3)
        let restarted = try load(makeStore()).get()
        XCTAssertNil(restarted.externalUserID)
        XCTAssertEqual(restarted.deviceID, "existing-device")
        XCTAssertNil(try legacyDevice())
    }

    private var identityKeys: [String] {
        [
            NotiflyCustomDefaultKey.projectId, NotiflyCustomDefaultKey.username,
            NotiflyCustomDefaultKey.deviceId, NotiflyCustomDefaultKey.externalUserId,
        ]
    }

    private func key(_ name: String) -> String { "\(projectID)_\(name)" }

    private func seed(deviceID: String? = "existing-device", userID: String? = "existing-user")
        throws
    {
        let defaults = try XCTUnwrap(defaults)
        defaults.set(projectID, forKey: key(NotiflyCustomDefaultKey.projectId))
        defaults.set("sdk-user", forKey: key(NotiflyCustomDefaultKey.username))
        defaults.set(deviceID, forKey: key(NotiflyCustomDefaultKey.deviceId))
        defaults.set(userID, forKey: key(NotiflyCustomDefaultKey.externalUserId))
    }

    private func identity(deviceID: String = "existing-device") -> StoredIdentity {
        StoredIdentity(
            projectID: projectID,
            deviceID: deviceID,
            externalUserID: "existing-user",
            username: "sdk-user"
        )
    }

    private func makeStore(readOnly: Bool = false) throws -> SharedIdentityStore {
        try SharedIdentityStore(
            projectID: projectID,
            accessGroup: "group.notifly.sdk-user",
            keychain: backend,
            legacy: LegacyIdentityStore(
                defaults: XCTUnwrap(defaults), projectID: projectID, username: "sdk-user"
            ),
            isReadOnly: readOnly,
            newDeviceID: {
                self.generationCount += 1; return "generated-device"
            }
        )
    }

    private func load(_ store: SharedIdentityStore, refresh: Bool = false) -> Result<
        StoredIdentity, Error
    > {
        let done = expectation(description: "load")
        var result: Result<StoredIdentity, Error> = .failure(IdentityMigrationError.identityUnavailable)
        worker.addTask { finish in
            defer { finish(); done.fulfill() }
            do {
                let identity = try store.load(forceRefresh: refresh)
                result = identity.map(Result.success) ?? .failure(IdentityMigrationError.identityUnavailable)
            } catch { result = .failure(error) }
        }
        wait(for: [done], timeout: 3)
        return result
    }

    private func update(_ store: SharedIdentityStore, userID: String?) -> Result<Void, Error> {
        let done = expectation(description: "update")
        var result: Result<Void, Error> = .failure(IdentityMigrationError.identityUnavailable)
        worker.addTask { finish in
            defer { finish() }
            do { try store.setExternalUserID(userID); result = .success(()) } catch { result = .failure(error) }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        return result
    }

    private func persisted() throws -> StoredIdentity {
        try JSONDecoder().decode(StoredIdentity.self, from: XCTUnwrap(backend.sharedData))
    }

    private func legacyDevice() throws -> String? {
        try XCTUnwrap(defaults).string(forKey: key(NotiflyCustomDefaultKey.deviceId))
    }

    private func assertFailure<Value, Failure: Error & Equatable>(
        _ result: Result<Value, Error>,
        _ expected: Failure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success: XCTFail("Expected failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? Failure, expected, file: file, line: line)
        }
    }
}

// Tests mutate injected state only before an operation or after awaiting completion.
// The identity store serializes I/O; hooks run within that same operation.
final class MigrationMemoryKeychain: KeychainProcessing, @unchecked Sendable {
    var sharedData: Data?
    var legacyData: Data?
    var readStatus: OSStatus?
    var writeStatus: OSStatus?
    var afterWrite: (() -> Void)?
    var beforeInsert: (() -> Void)?
    var onOperation: (() -> Void)?
    private(set) var writes = 0
    private(set) var legacyReads = 0

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        onOperation?()
        if query[kSecAttrAccessGroup as String] == nil {
            legacyReads += 1
            return legacyData.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
        }
        if let status = readStatus { return (status, nil) }
        return sharedData.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        XCTAssertNotNil(query[kSecAttrAccessGroup as String])
        beforeInsert?()
        guard sharedData == nil else { return errSecDuplicateItem }
        return write(query)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        XCTAssertNotNil(query[kSecAttrAccessGroup as String])
        guard sharedData != nil else { return errSecItemNotFound }
        return write(attributes)
    }

    private func write(_ attributes: [String: Any]) -> OSStatus {
        onOperation?()
        if let status = writeStatus { return status }
        sharedData = attributes[kSecValueData as String] as? Data
        writes += 1
        afterWrite?()
        return errSecSuccess
    }
}
