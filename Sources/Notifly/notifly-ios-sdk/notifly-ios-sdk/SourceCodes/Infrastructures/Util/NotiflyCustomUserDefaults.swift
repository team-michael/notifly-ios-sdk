//
//  NotiflyCustomUserDefaults.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

extension UserDefaults {
    static var notiflyShared: UserDefaults {
        let extensionGroupId = "group.tech.notifly"
        return UserDefaults(suiteName: extensionGroupId) ?? UserDefaults.standard
    }
}

enum NotiflyCustomUserDefaults {
    private static let notiflyUserDefaults = UserDefaults.notiflyShared
    private static var notiflyProjectIdKey = "notifly_project_id"
    static var projectIdInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyProjectIdKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyProjectIdKey)
            }
            notiflyUserDefaults.synchronize()
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyProjectIdKey)
            
        }
    }
    private static var notiflyUsernameKey = "notifly_username"
    static var usernameInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyUsernameKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyUsernameKey)
            }
            notiflyUserDefaults.synchronize()
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyUsernameKey)
        }
    }
    private static var notiflyPasswordKey = "notifly_password"
    static var passwordInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyPasswordKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyPasswordKey)
            }
            notiflyUserDefaults.synchronize()
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyPasswordKey)
        }
    }
    private static var notiflyAuthTokenKey = "notifly_authToken"
    static var authTokenInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyAuthTokenKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyAuthTokenKey)
            }
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyAuthTokenKey)
        }
    }
    
    private static var notiflyExternalUserIdKey = "notifly_external_user_id"
    static var externalUserIdInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyExternalUserIdKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyExternalUserIdKey)
            }
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyExternalUserIdKey)
        }
    }
    
    private static var notiflyDeviceIdKey = "notifly_deviceId"
    static var deviceIdInUserDefaults: String? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyDeviceIdKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyDeviceIdKey)
            }
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyDeviceIdKey)
        }
    }
    
    private static var notiflyIsRegisteredAPNsKey: String = "notifly_isRegisteredAPNs"
    static var isRegisteredAPNsInUserDefaults: Bool? {
        set {
            if let value = newValue {
                notiflyUserDefaults.set(value, forKey: notiflyIsRegisteredAPNsKey)
            } else {
                notiflyUserDefaults.removeObject(forKey: notiflyIsRegisteredAPNsKey)
            }
        }
        
        get {
            notiflyUserDefaults.string(forKey: notiflyIsRegisteredAPNsKey) != nil
        }
    }
}
