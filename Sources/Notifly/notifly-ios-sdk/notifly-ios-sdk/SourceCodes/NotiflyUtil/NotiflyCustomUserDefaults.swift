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
    
    private static func set(key: String, value: String?) -> Void {
        guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared, let projectId = NotiflyCustomUserDefaults.projectId else {
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
    
    static var projectIdInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.projectId, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.projectId)
        }
    }
    
    static var usernameInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.username, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.username)
        }
    }
    
    static var passwordInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.password, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.password)
        }
    }
    
    static var authTokenInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.authToken, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.authToken)
        }
    }
    
    static var externalUserIdInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.externalUserId, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.externalUserId)
        }
    }
    
    static var deviceIdInUserDefaults: String? {
        set {
            NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.deviceId, value: newValue)
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.deviceId)
        }
    }
    
    static var isRegisteredAPNsInUserDefaults: Bool? {
        set {
            if newValue == true {
                NotiflyCustomUserDefaults.set(key: NotiflyCustomDefaultKey.alreadyRegistered, value: "registered")
            }
        }
        get {
            return NotiflyCustomUserDefaults.get(key: NotiflyCustomDefaultKey.alreadyRegistered) != nil
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
