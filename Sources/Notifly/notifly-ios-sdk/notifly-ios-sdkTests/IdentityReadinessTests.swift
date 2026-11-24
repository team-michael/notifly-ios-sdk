import Foundation
import Security
import XCTest
@testable import notifly_ios_sdk

final class IdentityReadinessTests: XCTestCase {
    func testDirectGettersLoadAndMigrateWithoutPreloading() throws {
        let backend = MigrationMemoryKeychain()
        let defaults = try registerLegacyIdentity(keychain: backend)
        XCTAssertNil(NotiflyCustomUserDefaults.identityStore?.current)
        XCTAssertTrue(Thread.isMainThread)
        backend.onOperation = { XCTAssertTrue(Thread.isMainThread) }

        XCTAssertNotNil(try UserManager().getNotiflyUserID())
        XCTAssertEqual(AppHelper.getDeviceID(), "original-device")
        XCTAssertEqual(backend.writes, 1)
        XCTAssertNil(defaults.object(forKey: "startup-test_\(NotiflyCustomDefaultKey.deviceId)"))

        // Subsequent getters use the cache, even if the backend becomes unavailable.
        backend.readStatus = errSecInteractionNotAllowed
        XCTAssertEqual(AppHelper.getDeviceID(), "original-device")
        XCTAssertNotNil(try UserManager().getNotiflyUserID())
    }

    func testFailedDirectReadPreservesLegacyIdentityAndCanRetry() throws {
        let backend = MigrationMemoryKeychain()
        backend.readStatus = errSecInteractionNotAllowed
        let defaults = try registerLegacyIdentity(keychain: backend)
        XCTAssertNil(AppHelper.getDeviceID())
        XCTAssertThrowsError(try UserManager().getNotiflyUserID())
        XCTAssertEqual(
            defaults.string(forKey: "startup-test_\(NotiflyCustomDefaultKey.deviceId)"),
            "original-device"
        )
        XCTAssertEqual(backend.writes, 0)

        backend.readStatus = nil
        XCTAssertEqual(AppHelper.getDeviceID(), "original-device")
        XCTAssertNotNil(try UserManager().getNotiflyUserID())
    }

    func testSDKReadsTheMigratedIdentityAndUsesTheSameDeviceHash() throws {
        let projectID = "identity-integration-test"
        let suite = "tech.notifly.identity-integration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let deviceID = "original-Device-한글"
        defaults.set(deviceID, forKey: "\(projectID)_\(NotiflyCustomDefaultKey.deviceId)")
        defaults.set("original-user", forKey: "\(projectID)_\(NotiflyCustomDefaultKey.externalUserId)")
        NotiflyCustomUserDefaults.register(
            projectId: projectID, org: "sdk-user", defaults: defaults,
            keychain: MigrationMemoryKeychain()
        )
        XCTAssertEqual(AppHelper.getDeviceID(), deviceID)
        XCTAssertEqual(
            AppHelper.getNotiflyDeviceID(),
            UUID(name: deviceID, namespace: TrackingConstant.HashNamespace.deviceID)
                .notiflyStyleString
        )
        let users = UserManager()
        XCTAssertEqual(users.externalUserID, "original-user")
        // Golden UUIDv5 values preserve the legacy Optional representation for anonymous users.
        XCTAssertEqual(try users.getNotiflyUserID(), "12e523e77c4a59d3bca6102baf665bea")
        XCTAssertTrue(users.changeExternalUserId(newValue: nil))
        XCTAssertEqual(try users.getNotiflyUserID(), "1670faaa3386595a94432540fe22bda7")
        XCTAssertNil(defaults.object(forKey: "\(projectID)_\(NotiflyCustomDefaultKey.deviceId)"))
    }

    func testUserChangeFinishesOnTheNetworkCallbackThread() throws {
        let backend = MigrationMemoryKeychain()
        _ = try registerLegacyIdentity(keychain: backend)
        backend.onOperation = { XCTAssertFalse(Thread.isMainThread) }
        let done = expectation(description: "callback persists before returning")
        DispatchQueue.global().async {
            let users = UserManager()
            XCTAssertTrue(users.changeExternalUserId(newValue: "server-user"))
            XCTAssertEqual(users.externalUserID, "server-user")
            XCTAssertEqual(AppHelper.getDeviceID(), "original-device")
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    private func registerLegacyIdentity(keychain: MigrationMemoryKeychain) throws -> UserDefaults {
        let suite = "tech.notifly.startup-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set("original-device", forKey: "startup-test_\(NotiflyCustomDefaultKey.deviceId)")
        NotiflyCustomUserDefaults.register(
            projectId: "startup-test", org: "sdk-user", defaults: defaults, keychain: keychain
        )
        return defaults
    }
}
