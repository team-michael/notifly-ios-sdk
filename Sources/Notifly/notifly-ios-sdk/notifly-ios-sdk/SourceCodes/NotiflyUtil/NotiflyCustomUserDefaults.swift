//
//  NotiflyCustomUserDefaults.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

class NotiflyCustomUserDefaults {
    private static var projectId: String?
    private static var notiflyUserDefaultsShared: UserDefaults?

    private static let identityLock = NSLock()
    private static var configuredIdentityStore: SharedIdentityStore?
    private static var identityConfiguration: String?
    private static var identityError: Error = IdentityMigrationError.identityUnavailable

    static var identityStore: SharedIdentityStore? {
        identityLock.lock()
        defer { identityLock.unlock() }
        return configuredIdentityStore
    }

    static func register(
        projectId: String,
        org: String,
        isExtension: Bool = false,
        defaults: UserDefaults? = nil,
        keychain: KeychainProcessing = SystemKeychain()
    ) {
        // Capture UIKit's fallback before taking any storage lock. Reading Keychain
        // while another thread waits for this value must not require a main-queue hop.
        let fallbackDeviceID = isExtension ? nil : AppHelper.makeNewDeviceID()
        identityLock.lock()
        defer { identityLock.unlock() }
        let configuration = "\(projectId):\(org):\(isExtension)"
        if defaults == nil, identityConfiguration == configuration,
            configuredIdentityStore != nil
        {
            return
        }
        let shared = defaults ?? UserDefaults(suiteName: "group.notifly.\(org)") ?? .standard
        self.projectId = projectId
        notiflyUserDefaultsShared = shared
        identityConfiguration = configuration
        do {
            guard !org.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KeychainError.invalidConfiguration
            }
            configuredIdentityStore = try SharedIdentityStore(
                projectID: projectId,
                accessGroup: "group.notifly.\(org)",
                keychain: keychain,
                legacy: LegacyIdentityStore(
                    defaults: shared, projectID: projectId, username: org
                ),
                isReadOnly: isExtension,
                newDeviceID: { fallbackDeviceID }
            )
        } catch {
            configuredIdentityStore = nil
            identityError = error
        }
    }

    /// Reads synchronously on the caller. A cache miss may block for Keychain I/O.
    static func loadIdentity(forceRefresh: Bool = false) throws -> StoredIdentity {
        identityLock.lock()
        let store = configuredIdentityStore
        let error = identityError
        identityLock.unlock()
        guard let store = store else { throw error }
        guard let identity = try store.load(forceRefresh: forceRefresh), identityStore === store else {
            throw IdentityMigrationError.identityUnavailable
        }
        return identity
    }

    private static func readIdentity() -> StoredIdentity? {
        do {
            return try loadIdentity()
        } catch {
            Logger.error("Cannot read SDK identity: \(error)")
            return nil
        }
    }

    private static func get(key: String) -> String? {
        guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared,
            let projectId = NotiflyCustomUserDefaults.projectId
        else {
            return nil
        }
        let dataKey = "\(projectId)_\(key)"
        return shared.string(forKey: dataKey)
    }

    private static func set(key: String, value: String?) {
        guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared,
            let projectId = NotiflyCustomUserDefaults.projectId
        else {
            return
        }
        let dataKey = "\(projectId)_\(key)"
        if let value = value {
            shared.set(value, forKey: dataKey)
        } else {
            shared.removeObject(forKey: dataKey)
        }
        return
    }

    static var projectIdInUserDefaults: String? { readIdentity()?.projectID }
    static var usernameInUserDefaults: String? { readIdentity()?.username }

    static var passwordInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.password)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.password, value: newValue)
        }
    }

    static var authTokenInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.authToken)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.authToken, value: newValue)
        }
    }

    static var externalUserIdInUserDefaults: String? { readIdentity()?.externalUserID }
    static var deviceIdInUserDefaults: String? { readIdentity()?.deviceID }

    static var isRegisteredAPNsInUserDefaults: Bool? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.alreadyRegistered)
                != nil
        }
        set {
            if newValue == true {
                NotiflyCustomUserDefaults.set(
                    key: NotiflyCustomDefaultKey.alreadyRegistered, value: "registered")
            }
        }
    }
}

enum NotiflyCustomDefaultKey {
    static let projectId = "notifly_project_id"
    static let username = "notifly_username"
    static let password = "notifly_password"
    static let externalUserId = "notifly_external_user_id"
    static let authToken = "notifly_authToken"
    static let deviceId = "notifly_deviceId"
    static let alreadyRegistered = "notifly_isRegisteredAPNs"
}
