// Simulator-only integration fixture. Uses synthetic values and never initializes the SDK.
import Foundation
import Security

func finish(_ result: [String: Any]) -> Never {
    do {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("result.json"), options: .atomic)
    } catch {
        FileHandle.standardError.write(Data("Cannot write probe result: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

func failure(_ error: Error) -> Never {
    if case KeychainError.keychain(let status) = error {
        finish(["status": status])
    } else {
        finish(["error": String(describing: error)])
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    finish(["error": "expected action and project ID"])
}
let action = arguments[1]
let projectID = arguments[2]
let store: SharedIdentityStore
do {
    store = try SharedIdentityStore(
        projectID: projectID,
        accessGroup: "group.notifly.keychain-module-test"
    )
} catch {
    failure(error)
}
switch action {
case "seed-legacy", "migrate", "read-migrated", "logout-migrated":
    guard let defaults = UserDefaults(suiteName: "group.notifly.keychain-module-test") else {
        finish(["error": "test defaults unavailable"])
    }
    let deviceKey = "\(projectID)_\(NotiflyCustomDefaultKey.deviceId)"
    if action == "seed-legacy" {
        defaults.set(projectID, forKey: "\(projectID)_\(NotiflyCustomDefaultKey.projectId)")
        defaults.set(
            "keychain-module-test",
            forKey: "\(projectID)_\(NotiflyCustomDefaultKey.username)"
        )
        defaults.set("legacy-device", forKey: deviceKey)
        defaults.set(
            "legacy-user",
            forKey: "\(projectID)_\(NotiflyCustomDefaultKey.externalUserId)"
        )
        defaults.synchronize()
        finish(["seeded": true])
    }
    do {
        let backend = SystemKeychain()
        let migrating = try SharedIdentityStore(
            projectID: projectID,
            accessGroup: "group.notifly.keychain-module-test",
            keychain: backend,
            legacy: LegacyIdentityStore(
                defaults: defaults, projectID: projectID, username: "keychain-module-test"
            ),
            isReadOnly: action == "read-migrated"
        )
        func report(_ identity: StoredIdentity?) -> Never {
            defaults.synchronize()
            finish([
                "deviceId": identity?.deviceID ?? "",
                "externalUserId": identity?.externalUserID ?? "",
                "legacyPresent": defaults.object(forKey: deviceKey) != nil,
            ])
        }
        let identity = try migrating.load()
        if action == "logout-migrated" {
            try migrating.setExternalUserID(nil)
            report(migrating.current)
        } else {
            report(identity)
        }
    } catch { failure(error) }
case "write", "logout":
    let value = StoredIdentity(
        projectID: projectID,
        deviceID: "synthetic-device",
        externalUserID: action == "write" ? "synthetic-user" : nil,
        username: "synthetic-sdk-user"
    )
    do {
        try store.save(value)
        finish(["status": 0])
    } catch { failure(error) }
case "read":
    do {
        let value = try store.load(forceRefresh: true)
        finish([
            "status": 0, "found": value != nil,
            "deviceId": value?.deviceID ?? "", "externalUserId": value?.externalUserID ?? "",
        ])
    } catch { failure(error) }
case "attributes", "delete":
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "tech.notifly.identity",
        kSecAttrAccount as String: projectID,
        kSecAttrAccessGroup as String: "group.notifly.keychain-module-test",
        kSecAttrSynchronizable as String: false,
    ]
    if action == "delete" {
        finish(["status": SecItemDelete(query as CFDictionary)])
    }
    query[kSecReturnAttributes as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    let attributes = result as? [String: Any] ?? [:]
    finish([
        "status": status,
        "accessible": attributes[kSecAttrAccessible as String] as? String ?? "",
        "accessGroup": attributes[kSecAttrAccessGroup as String] as? String ?? "",
        "synchronizable": attributes[kSecAttrSynchronizable as String] as? Bool ?? true,
    ])
default: finish(["error": "unknown action"])
}
