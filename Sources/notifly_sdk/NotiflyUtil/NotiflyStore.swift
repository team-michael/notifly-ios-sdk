//
//  NotiflyStore.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

final class NotiflyStore {

    private static var projectId: String?
    private static var notiflyUserDefaultsShared: UserDefaults?
    private static let identityLock = NSLock()
    private static var identityRegistration: IdentityRegistration?
    private static var identityError: Error = IdentityStoreError.identityUnavailable

    static func register(
        projectId: String,
        org: String,
        isExtension: Bool = false,
        defaults: UserDefaults? = nil,
        keychain: KeychainProcessing = SystemKeychain(),
        newDeviceID: String? = nil
    ) {
        // Obtain UIKit data before taking storage locks. Keychain operations never hop queues.
        let deviceID = isExtension ? nil : (newDeviceID ?? AppHelper.makeNewDeviceID())
        identityLock.lock()
        defer { identityLock.unlock() }
        if defaults == nil, let registration = identityRegistration,
            registration.initialIdentity.projectID == projectId,
            registration.initialIdentity.username == org,
            registration.isExtension == isExtension
        {
            return
        }
        let shared = defaults ?? UserDefaults(suiteName: "group.notifly.\(org)") ?? .standard
        self.projectId = projectId
        notiflyUserDefaultsShared = shared
        identityRegistration = nil
        do {
            guard !org.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KeychainError.invalidConfiguration
            }
            let keychain = try Keychain<StoredIdentity>(
                service: "tech.notifly.identity",
                account: projectId,
                accessGroup: "group.notifly.\(org)",
                keychain: keychain
            )
            let store = try IdentityStore(
                projectID: projectId,
                defaults: shared,
                keychain: keychain,
                isReadOnly: isExtension,
                username: org
            )
            identityRegistration = IdentityRegistration(
                store: store,
                initialIdentity: StoredIdentity(
                    projectID: projectId, username: org, deviceID: deviceID, externalUserID: nil
                ),
                isExtension: isExtension
            )
        }
        catch {
            identityError = error
        }
    }

    /// Reads synchronously. Cold reads and pending writes may delay the calling thread.
    static func loadIdentity() throws -> StoredIdentity {
        try loadIdentity(for: registeredIdentity())
    }

    private static func loadIdentity(for registration: IdentityRegistration) throws -> StoredIdentity {
        if registration.isExtension {
            guard let identity = try registration.store.load() else {
                throw IdentityStoreError.identityUnavailable
            }
            return identity
        }
        let initial = registration.initialIdentity
        return try registration.store.load(
            orCreate: StoredIdentity(
                projectID: initial.projectID,
                username: initial.username,
                deviceID: initial.deviceID ?? AppHelper.makeNewDeviceID(),
                externalUserID: nil
            )
        )
    }

    static func setExternalUserID(_ value: String?) throws {
        let registration = try registeredIdentity()
        guard !registration.isExtension else { throw IdentityStoreError.readOnly }
        _ = try loadIdentity(for: registration)
        try registration.store.setExternalUserID(value)
    }

    private static func registeredIdentity() throws -> IdentityRegistration {
        identityLock.lock()
        defer { identityLock.unlock() }
        guard let registration = identityRegistration else { throw identityError }
        return registration
    }

    private static func readIdentity() -> StoredIdentity? {
        do {
            return try loadIdentity()
        }
        catch {
            Logger.error("Cannot read SDK identity: \(error)")
            return nil
        }
    }

    private static func get(key: String) -> String? {
        identityLock.lock()
        defer { identityLock.unlock() }
        guard let shared = NotiflyStore.notiflyUserDefaultsShared,
            let projectId = NotiflyStore.projectId
        else {
            return nil
        }
        let dataKey = "\(projectId)_\(key)"
        return shared.string(forKey: dataKey)
    }

    private static func set(key: String, value: String?) {
        identityLock.lock()
        defer { identityLock.unlock() }
        guard let shared = NotiflyStore.notiflyUserDefaultsShared,
            let projectId = NotiflyStore.projectId
        else {
            return
        }
        let dataKey = "\(projectId)_\(key)"
        if let value = value {
            shared.set(value, forKey: dataKey)
        }
        else {
            shared.removeObject(forKey: dataKey)
        }
        return
    }

    static var projectID: String? { readIdentity()?.projectID }
    static var username: String? { readIdentity()?.username }

    static var password: String? {
        get {
            return NotiflyStore.get(key: NotiflyCustomDefaultKey.password)
        }
        set {
            NotiflyStore.set(key: NotiflyCustomDefaultKey.password, value: newValue)
        }
    }

    static var authToken: String? {
        get {
            return NotiflyStore.get(key: NotiflyCustomDefaultKey.authToken)
        }
        set {
            NotiflyStore.set(key: NotiflyCustomDefaultKey.authToken, value: newValue)
        }
    }

    static var externalUserID: String? { readIdentity()?.externalUserID }
    static var deviceID: String? { readIdentity()?.deviceID }

    static var isRegisteredAPNs: Bool? {
        get {
            return NotiflyStore.get(key: NotiflyCustomDefaultKey.alreadyRegistered)
                != nil
        }
        set {
            if newValue == true {
                NotiflyStore.set(
                    key: NotiflyCustomDefaultKey.alreadyRegistered,
                    value: "registered"
                )
            }
        }
    }
}

private struct IdentityRegistration {

    let store: IdentityStore
    let initialIdentity: StoredIdentity
    let isExtension: Bool
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
