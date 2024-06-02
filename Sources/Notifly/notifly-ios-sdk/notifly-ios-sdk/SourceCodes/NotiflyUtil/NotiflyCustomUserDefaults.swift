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

    static func register(projectId: String, org: String) {
        NotiflyCustomUserDefaults.projectId = projectId
        NotiflyCustomUserDefaults.notiflyUserDefaultsShared = UserDefaults(suiteName: "group.notifly.\(org)") ?? UserDefaults.standard
    }

    private static func get(key: String) -> String? {
        guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared, let projectId = NotiflyCustomUserDefaults.projectId else {
            return nil
        }
        let dataKey = "\(projectId)_\(key)"
        return shared.string(forKey: dataKey)
    }

    private static func set(key: String, value: String?) {
        guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared, let projectId = NotiflyCustomUserDefaults.projectId else {
            return
        }
        let dataKey = "\(projectId)_\(key)"
        if let value = value {
            shared.set(value, forKey: dataKey)
        } else {
            shared.removeObject(forKey: dataKey)
        }
    }

    static var projectIdInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.projectId)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.projectId, value: newValue)
        }
    }

    static var usernameInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.username)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.username, value: newValue)
        }
    }

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

    static var externalUserIdInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.externalUserId)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.externalUserId, value: newValue)
        }
    }

    static var deviceIdInUserDefaults: String? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.deviceId)
        }
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.deviceId, value: newValue)
        }
    }

    static var isRegisteredAPNsInUserDefaults: Bool? {
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.alreadyRegistered) != nil
        }
        set {
            if newValue == true {
                NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.alreadyRegistered, value: "registered")
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
