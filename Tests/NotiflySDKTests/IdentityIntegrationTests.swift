import Foundation
import Security
import UserNotifications
import XCTest
@testable import notifly_sdk

final class IdentityIntegrationTests: XCTestCase {

    private let projectID = "identity-integration-test"
    private let username = "sdk-user"
    private let deviceID = "original-Device-한글"

    func testUpgradePreservesUserAndDeviceHashesAndOnlyRemovesIdentifiers() throws {
        let fixture = try register()
        NotiflyStore.password = "password"
        NotiflyStore.authToken = "token"
        NotiflyStore.isRegisteredAPNs = true
        let users = UserManager()

        XCTAssertEqual(try users.getNotiflyUserID(), "12e523e77c4a59d3bca6102baf665bea")
        XCTAssertEqual(AppHelper.getDeviceID(), deviceID)
        XCTAssertEqual(AppHelper.getNotiflyDeviceID()?.lowercased(), "44ad3d8cb42257f6a8f61644c35a68b6")
        XCTAssertEqual(users.externalUserID, "original-user")
        XCTAssertEqual(NotiflyStore.projectID, projectID)
        XCTAssertEqual(NotiflyStore.username, username)
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_project_id")))
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_deviceId")))
        XCTAssertEqual(NotiflyStore.password, "password")
        XCTAssertEqual(NotiflyStore.authToken, "token")
        XCTAssertEqual(NotiflyStore.isRegisteredAPNs, true)

        XCTAssertTrue(users.changeExternalUserId(newValue: nil))
        XCTAssertEqual(try users.getNotiflyUserID(), "1670faaa3386595a94432540fe22bda7")
        XCTAssertEqual(AppHelper.getDeviceID(), deviceID)
    }

    func testFreshInstallPersistsOnceAndRegistrationDoesNotRecreateMarker() throws {
        let fixture = try register(hasLegacy: false)
        let identity = try NotiflyStore.loadIdentity()
        XCTAssertEqual(identity.projectID, projectID)
        XCTAssertEqual(identity.username, username)
        XCTAssertEqual(identity.deviceID, "new-device")
        XCTAssertNil(identity.externalUserID)
        XCTAssertEqual(fixture.backend.writes, 1)

        NotiflyStore.register(projectId: projectID, org: username)
        XCTAssertEqual(try NotiflyStore.loadIdentity(), identity)
        XCTAssertEqual(fixture.backend.writes, 1)
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_project_id")))
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_username")))
    }

    func testPartialLegacyStateKeepsUserAndFillsOnlyMissingRegistrationFields() throws {
        let fixture = try register()
        fixture.defaults.removeObject(forKey: legacyKey("notifly_deviceId"))
        fixture.defaults.removeObject(forKey: legacyKey("notifly_username"))
        let identity = try NotiflyStore.loadIdentity()
        XCTAssertEqual(identity.deviceID, "new-device")
        XCTAssertEqual(identity.username, username)
        XCTAssertEqual(identity.externalUserID, "original-user")
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_project_id")))
    }

    func testLockedStorageDoesNotGenerateOrReplaceIdentityAndCanRetry() throws {
        let fixture = try register()
        fixture.backend.readStatus = errSecInteractionNotAllowed
        let users = UserManager()
        XCTAssertThrowsError(try users.getNotiflyUserID())
        XCTAssertNil(AppHelper.getDeviceID())
        XCTAssertFalse(users.changeExternalUserId(newValue: "new-user"))
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertEqual(fixture.defaults.string(forKey: legacyKey("notifly_deviceId")), deviceID)

        fixture.backend.readStatus = nil
        XCTAssertEqual(try users.getNotiflyUserID(), "12e523e77c4a59d3bca6102baf665bea")
    }

    func testFailedNewInstallWriteDoesNotPublishUnpersistedID() throws {
        let fixture = try register(hasLegacy: false)
        fixture.backend.writeStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try UserManager().getNotiflyUserID())
        XCTAssertNil(AppHelper.getDeviceID())
        XCTAssertNil(fixture.backend.data)
        XCTAssertNil(fixture.defaults.object(forKey: legacyKey("notifly_deviceId")))

        fixture.backend.writeStatus = nil
        XCTAssertEqual(try NotiflyStore.loadIdentity().deviceID, "new-device")
    }

    func testMissingMarkerWithRemainingIdentifiersDoesNotCreateNewIdentity() throws {
        let fixture = try register()
        fixture.defaults.removeObject(forKey: legacyKey("notifly_project_id"))
        XCTAssertThrowsError(try NotiflyStore.loadIdentity())
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertEqual(fixture.defaults.string(forKey: legacyKey("notifly_external_user_id")), "original-user")
    }

    func testFailedUserChangePreservesCurrentIdentityAndHash() throws {
        let fixture = try register()
        let users = UserManager()
        let originalID = try users.getNotiflyUserID()
        fixture.backend.writeStatus = errSecInteractionNotAllowed
        XCTAssertFalse(users.changeExternalUserId(newValue: "new-user"))
        XCTAssertFalse(users.changeExternalUserId(newValue: nil))
        XCTAssertEqual(users.externalUserID, "original-user")
        XCTAssertEqual(try users.getNotiflyUserID(), originalID)
        XCTAssertEqual(try storedIdentity(fixture.backend).externalUserID, "original-user")
    }

    func testSuccessfulUserChangeUpdatesCacheWhenKeychainReadsBecomeUnavailable() throws {
        for newUserID: String? in ["server-user", nil] {
            let fixture = try register()
            let users = UserManager()
            let originalID = try users.getNotiflyUserID()
            fixture.backend.afterWrite = { fixture.backend.readStatus = errSecInteractionNotAllowed }

            XCTAssertTrue(users.changeExternalUserId(newValue: newUserID))
            XCTAssertEqual(users.externalUserID, newUserID)
            XCTAssertNotEqual(try users.getNotiflyUserID(), originalID)
            XCTAssertEqual(AppHelper.getDeviceID(), deviceID)
            XCTAssertEqual(try storedIdentity(fixture.backend).externalUserID, newUserID)

            fixture.backend.readStatus = nil
            XCTAssertEqual(users.externalUserID, newUserID)
        }
    }

    func testDirectReadsStayOnCallerAndNetworkCallbackPersistsSynchronously() throws {
        let fixture = try register()
        XCTAssertTrue(Thread.isMainThread)
        fixture.backend.onOperation = { XCTAssertTrue(Thread.isMainThread) }
        let users = UserManager()
        _ = try users.getNotiflyUserID()

        fixture.backend.onOperation = { XCTAssertFalse(Thread.isMainThread) }
        let done = expectation(description: "network callback finishes after persistence")
        DispatchQueue.global().async {
            XCTAssertTrue(users.changeExternalUserId(newValue: "server-user"))
            XCTAssertEqual(users.externalUserID, "server-user")
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(try storedIdentity(fixture.backend).externalUserID, "server-user")
    }

    func testExtensionReadsLegacyAndLaterAppChangesWithoutWriting() throws {
        let fixture = try register(isExtension: true)
        let legacy = try NotiflyStore.loadIdentity()
        XCTAssertEqual(legacy.deviceID, deviceID)
        XCTAssertThrowsError(try NotiflyStore.setExternalUserID(nil))
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertNotNil(fixture.defaults.object(forKey: legacyKey("notifly_project_id")))

        let loggedOut = StoredIdentity(
            projectID: projectID, username: username, deviceID: deviceID, externalUserID: nil
        )
        fixture.backend.data = try JSONEncoder().encode(loggedOut)
        XCTAssertEqual(try NotiflyStore.loadIdentity(), loggedOut)
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertNotNil(fixture.defaults.object(forKey: legacyKey("notifly_project_id")))
    }

    func testExtensionDoesNotGenerateIdentityBeforeHostAppRuns() throws {
        let fixture = try register(hasLegacy: false, isExtension: true)
        XCTAssertThrowsError(try NotiflyStore.loadIdentity())
        XCTAssertNil(AppHelper.getDeviceID())
        XCTAssertEqual(fixture.backend.writes, 0)
    }

    func testExtensionStillDeliversContentWhenKeychainCannotBeRead() throws {
        let fixture = try register(isExtension: true)
        fixture.backend.readStatus = errSecInteractionNotAllowed
        let service = NotiflyNotificationServiceExtension()
        service.register(projectId: projectID, username: username)
        let content = UNMutableNotificationContent()
        content.body = "test notification"
        content.userInfo = ["notifly_message_type": "push-notification"]
        let request = UNNotificationRequest(identifier: "identity-test", content: content, trigger: nil)
        let delivered = expectation(description: "notification content is returned")
        service.didReceive(request) { result in
            XCTAssertEqual(result.body, content.body)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(fixture.backend.writes, 0)
    }

    func testDifferentOrganizationCannotMigrateOrEraseStoredIdentifiers() throws {
        let fixture = try register()
        fixture.defaults.set("different-org", forKey: legacyKey("notifly_username"))
        XCTAssertThrowsError(try NotiflyStore.loadIdentity())
        XCTAssertEqual(fixture.backend.writes, 0)
        XCTAssertEqual(fixture.defaults.string(forKey: legacyKey("notifly_username")), "different-org")
    }

    private func storedIdentity(_ backend: IdentityTestKeychain) throws -> StoredIdentity {
        try JSONDecoder().decode(StoredIdentity.self, from: XCTUnwrap(backend.data))
    }

    private func legacyKey(_ name: String) -> String { "\(projectID)_\(name)" }

    private func register(
        hasLegacy: Bool = true,
        isExtension: Bool = false
    ) throws -> (defaults: UserDefaults, backend: IdentityTestKeychain) {
        let suite = "tech.notifly.identity-integration-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        if hasLegacy {
            defaults.set(projectID, forKey: legacyKey("notifly_project_id"))
            defaults.set(username, forKey: legacyKey("notifly_username"))
            defaults.set(deviceID, forKey: legacyKey("notifly_deviceId"))
            defaults.set("original-user", forKey: legacyKey("notifly_external_user_id"))
        }
        let backend = IdentityTestKeychain()
        NotiflyStore.register(
            projectId: projectID,
            org: username,
            isExtension: isExtension,
            defaults: defaults,
            keychain: backend,
            newDeviceID: "new-device"
        )
        return (defaults, backend)
    }
}
