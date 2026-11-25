import Foundation
import Security
import XCTest
@testable import notifly_sdk

final class IdentityStoreTests: XCTestCase {

    private let identity = StoredIdentity(
        projectID: "project", username: "org", deviceID: "original-Device-한글", externalUserID: "user"
    )

    func testProjectMarkerMigratesExactIdentifiersAndOnlyRemovesTheirKeys() throws {
        let fixture = try makeFixture()
        let untouched = [
            "project_notifly_password": "password",
            "project_notifly_authToken": "token",
            "project_notifly_isRegisteredAPNs": "registered",
            "other_notifly_deviceId": "other-device"
        ]
        for (key, value) in untouched { fixture.defaults.set(value, forKey: key) }

        XCTAssertEqual(try fixture.store.load(), identity)
        XCTAssertEqual(try fixture.keychain.load(), identity)
        for key in legacyValues.keys { XCTAssertNil(fixture.defaults.object(forKey: key)) }
        for (key, value) in untouched { XCTAssertEqual(fixture.defaults.string(forKey: key), value) }
        XCTAssertEqual(fixture.backend.writes, 1)
    }

    func testMissingMarkerDoesNotMigrateOrDeleteRemainingValues() throws {
        let fixture = try makeFixture()
        fixture.defaults.removeObject(forKey: "project_notifly_project_id")
        XCTAssertNil(try fixture.store.load())
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertEqual(fixture.defaults.string(forKey: "project_notifly_external_user_id"), "user")

        fixture.defaults.set("project", forKey: "project_notifly_project_id")
        XCTAssertEqual(try fixture.store.load(), identity)
    }

    func testMarkerAloneMigratesWithoutGeneratingMissingIdentifiers() throws {
        let fixture = try makeFixture(hasLegacy: false)
        fixture.defaults.set("project", forKey: "project_notifly_project_id")
        let migrated = try XCTUnwrap(fixture.store.load())
        XCTAssertEqual(migrated.projectID, "project")
        XCTAssertNil(migrated.username)
        XCTAssertNil(migrated.deviceID)
        XCTAssertNil(migrated.externalUserID)
        XCTAssertEqual(try fixture.keychain.load(), migrated)
    }

    func testExistingKeychainResumesCleanupWithoutAnotherWrite() throws {
        let fixture = try makeFixture(stored: identity)
        fixture.defaults.removeObject(forKey: "project_notifly_external_user_id")
        XCTAssertEqual(try fixture.store.load(), identity)
        XCTAssertEqual(fixture.backend.writes, 0)
        for key in legacyValues.keys { XCTAssertNil(fixture.defaults.object(forKey: key)) }
    }

    func testVerifiedKeychainCleansRemainingKeysEvenIfMarkerWasAlreadyRemoved() throws {
        let fixture = try makeFixture(stored: identity)
        fixture.defaults.removeObject(forKey: "project_notifly_project_id")
        XCTAssertEqual(try fixture.store.load(), identity)
        for key in legacyValues.keys { XCTAssertNil(fixture.defaults.object(forKey: key)) }
    }

    func testKeychainAccessFailuresPreserveLegacyAndBlockWrites() throws {
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement] {
            let fixture = try makeFixture()
            fixture.backend.readStatus = status
            XCTAssertThrowsError(try fixture.store.load()) { error in
                XCTAssertEqual(error as? KeychainError, .status(status))
            }
            XCTAssertThrowsError(try fixture.store.save(identity))
            assertLegacyPreserved(fixture.defaults)
            XCTAssertEqual(fixture.backend.writes, 0)
        }
    }

    func testCorruptKeychainIsNotOverwritten() throws {
        let fixture = try makeFixture()
        let corruptData = Data("invalid JSON".utf8)
        fixture.backend.data = corruptData
        XCTAssertThrowsError(try fixture.store.load())
        XCTAssertThrowsError(try fixture.store.save(identity))
        XCTAssertEqual(fixture.backend.data, corruptData)
        assertLegacyPreserved(fixture.defaults)
    }

    func testMalformedOrForeignLegacyValuesAreNotMigrated() throws {
        for (key, value) in [
            ("project_notifly_project_id", "other" as Any),
            ("project_notifly_deviceId", 123 as Any)
        ] {
            let fixture = try makeFixture()
            fixture.defaults.set(value, forKey: key)
            XCTAssertThrowsError(try fixture.store.load())
            XCTAssertNotNil(fixture.defaults.object(forKey: key))
            XCTAssertEqual(fixture.backend.writes, 0)
        }
    }

    func testFailedMigrationWritePreservesOriginalValues() throws {
        let fixture = try makeFixture()
        fixture.backend.writeStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try fixture.store.load())
        assertLegacyPreserved(fixture.defaults)
        XCTAssertNil(fixture.backend.data)
    }

    func testReadbackFailureKeepsMarkerAndNextLoadResumesCleanup() throws {
        let fixture = try makeFixture()
        fixture.backend.afterWrite = { fixture.backend.readStatus = errSecInteractionNotAllowed }
        XCTAssertThrowsError(try fixture.store.load())
        XCTAssertThrowsError(try fixture.store.load())
        assertLegacyPreserved(fixture.defaults)

        fixture.backend.readStatus = nil
        XCTAssertEqual(try fixture.store.load(), identity)
        XCTAssertNil(fixture.defaults.object(forKey: "project_notifly_project_id"))
        XCTAssertEqual(fixture.backend.writes, 1)
    }

    func testMismatchedReadbackDoesNotDeleteLegacy() throws {
        let fixture = try makeFixture()
        fixture.backend.afterWrite = { fixture.backend.data = nil }
        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? IdentityStoreError, .verificationFailed)
        }
        assertLegacyPreserved(fixture.defaults)
    }

    func testLegacyChangeDuringCopyIsNotDeleted() throws {
        let fixture = try makeFixture()
        fixture.backend.afterWrite = {
            fixture.defaults.set("new-user", forKey: "project_notifly_external_user_id")
        }
        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? IdentityStoreError, .legacyChanged)
        }
        XCTAssertEqual(fixture.defaults.string(forKey: "project_notifly_project_id"), "project")
        XCTAssertEqual(fixture.defaults.string(forKey: "project_notifly_external_user_id"), "new-user")
    }

    func testConflictingKeychainAndLegacyValuesArePreserved() throws {
        let fixture = try makeFixture(stored: identity)
        fixture.defaults.set("different-device", forKey: "project_notifly_deviceId")
        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? IdentityStoreError, .conflictingIdentity)
        }
        XCTAssertEqual(try fixture.keychain.load(), identity)
        XCTAssertEqual(fixture.defaults.string(forKey: "project_notifly_deviceId"), "different-device")
        XCTAssertNotNil(fixture.defaults.object(forKey: "project_notifly_project_id"))
    }

    func testReadOnlyStoreObservesAppChangesWithoutMigratingOrCleaning() throws {
        let fixture = try makeFixture(isReadOnly: true)
        XCTAssertEqual(try fixture.store.load(), identity)
        XCTAssertThrowsError(try fixture.store.save(identity)) { error in
            XCTAssertEqual(error as? IdentityStoreError, .readOnly)
        }
        let loggedOut = StoredIdentity(
            projectID: "project", username: "org", deviceID: identity.deviceID, externalUserID: nil
        )
        fixture.backend.data = try JSONEncoder().encode(loggedOut)
        XCTAssertEqual(try fixture.store.load(), loggedOut)
        assertLegacyPreserved(fixture.defaults)
        XCTAssertEqual(fixture.backend.writes, 0)
    }

    func testSaveMigratesFirstThenPersistsLogoutAndUpdatesCache() throws {
        let fixture = try makeFixture()
        let loggedOut = StoredIdentity(
            projectID: "project", username: "org", deviceID: identity.deviceID, externalUserID: nil
        )
        try fixture.store.save(loggedOut)
        XCTAssertEqual(try fixture.keychain.load(), loggedOut)
        XCTAssertEqual(fixture.backend.writes, 2)
        XCTAssertNil(fixture.defaults.object(forKey: "project_notifly_project_id"))

        fixture.backend.readStatus = errSecInteractionNotAllowed
        XCTAssertEqual(try fixture.store.load(), loggedOut)
    }

    func testFailedUpdateKeepsPreviousStoredAndCachedIdentity() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.load()
        fixture.backend.writeStatus = errSecInteractionNotAllowed
        let changed = StoredIdentity(
            projectID: "project", username: "org", deviceID: identity.deviceID, externalUserID: "new"
        )
        XCTAssertThrowsError(try fixture.store.save(changed))
        XCTAssertEqual(try fixture.store.load(), identity)
        XCTAssertEqual(try fixture.keychain.load(), identity)
    }

    func testForeignProjectCannotBeLoadedOrSaved() throws {
        let foreign = StoredIdentity(
            projectID: "other", username: "org", deviceID: "device", externalUserID: nil
        )
        let fixture = try makeFixture(stored: foreign)
        XCTAssertThrowsError(try fixture.store.load())
        XCTAssertThrowsError(try fixture.store.save(identity))
        XCTAssertThrowsError(try fixture.store.save(foreign))
        XCTAssertEqual(try fixture.keychain.load(), foreign)
        assertLegacyPreserved(fixture.defaults)
        XCTAssertEqual(fixture.backend.writes, 0)
    }

    func testConcurrentLoadsPerformOneMigration() throws {
        let fixture = try makeFixture()
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                let loaded = try fixture.store.load()
                XCTAssertEqual(loaded, identity)
            } catch {
                XCTFail("Concurrent identity load failed: \(error)")
            }
        }
        XCTAssertEqual(fixture.backend.writes, 1)
        XCTAssertEqual(try fixture.keychain.load(), identity)
    }

    private var legacyValues: [String: String] {
        [
            "project_notifly_project_id": "project",
            "project_notifly_username": "org",
            "project_notifly_deviceId": "original-Device-한글",
            "project_notifly_external_user_id": "user"
        ]
    }

    private func assertLegacyPreserved(_ defaults: UserDefaults, file: StaticString = #filePath, line: UInt = #line) {
        for (key, value) in legacyValues {
            XCTAssertEqual(defaults.string(forKey: key), value, file: file, line: line)
        }
    }

    private func makeFixture(
        hasLegacy: Bool = true,
        stored: StoredIdentity? = nil,
        isReadOnly: Bool = false
    ) throws -> IdentityFixture {
        let suite = "tech.notifly.identity-store-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        if hasLegacy {
            for (key, value) in legacyValues { defaults.set(value, forKey: key) }
        }
        let backend = IdentityTestKeychain()
        backend.data = try stored.map { try JSONEncoder().encode($0) }
        let keychain = try Keychain<StoredIdentity>(
            service: "test.identity", account: "project", accessGroup: "group.test", keychain: backend
        )
        let store = try IdentityStore(
            projectID: "project", defaults: defaults, keychain: keychain, isReadOnly: isReadOnly
        )
        return IdentityFixture(defaults: defaults, backend: backend, keychain: keychain, store: store)
    }
}

private struct IdentityFixture {

    let defaults: UserDefaults
    let backend: IdentityTestKeychain
    let keychain: Keychain<StoredIdentity>
    let store: IdentityStore
}

// The tested store serializes access; fixtures are inspected only after operations finish.
final class IdentityTestKeychain: KeychainProcessing {

    var data: Data?
    var readStatus: OSStatus?
    var writeStatus: OSStatus?
    var afterWrite: (() -> Void)?
    var onOperation: (() -> Void)?
    var writes = 0

    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        onOperation?()
        if let readStatus = readStatus { return (readStatus, nil) }
        guard let data = data else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as NSData)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        onOperation?()
        guard data == nil else { return errSecDuplicateItem }
        return write(attributes)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        onOperation?()
        guard data != nil else { return errSecItemNotFound }
        return write(attributes)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        XCTFail("Identity migration must not delete Keychain items")
        return errSecUnimplemented
    }

    private func write(_ attributes: [String: Any]) -> OSStatus {
        if let writeStatus = writeStatus { return writeStatus }
        data = attributes[kSecValueData as String] as? Data
        writes += 1
        let callback = afterWrite
        afterWrite = nil
        callback?()
        return errSecSuccess
    }
}
