//
//  NotiflyCustomUserDefaults.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

class NotiflyCustomUserDefaults {
    private static var notiflyUserDefaultsShared: UserDefaults?
    static func register(notiflyUserName: String) {
        NotiflyCustomUserDefaults.notiflyUserDefaultsShared = UserDefaults(suiteName: "group.notifly.\(notiflyUserName)") ?? UserDefaults.standard
    }
    
    private static var notiflyProjectIdKey = "notifly_project_id"
    static var projectIdInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyProjectIdKey)
            } else {
                shared.removeObject(forKey: notiflyProjectIdKey)
            }
            shared.synchronize()
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyProjectIdKey)
        }
    }
    private static var notiflyUsernameKey = "notifly_username"
    static var usernameInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyUsernameKey)
            } else {
                shared.removeObject(forKey: notiflyUsernameKey)
            }
            shared.synchronize()
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyUsernameKey)
        }
    }
    private static var notiflyPasswordKey = "notifly_password"
    static var passwordInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyPasswordKey)
            } else {
                shared.removeObject(forKey: notiflyPasswordKey)
            }
            shared.synchronize()
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyPasswordKey)
        }
    }
    private static var notiflyAuthTokenKey = "notifly_authToken"
    static var authTokenInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyAuthTokenKey)
            } else {
                shared.removeObject(forKey: notiflyAuthTokenKey)
            }
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyAuthTokenKey)
        }
    }
    
    private static var notiflyExternalUserIdKey = "notifly_external_user_id"
    static var externalUserIdInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyExternalUserIdKey)
            } else {
                shared.removeObject(forKey: notiflyExternalUserIdKey)
            }
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyExternalUserIdKey)
        }
    }
    
    private static var notiflyDeviceIdKey = "notifly_deviceId"
    static var deviceIdInUserDefaults: String? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyDeviceIdKey)
            } else {
                shared.removeObject(forKey: notiflyDeviceIdKey)
            }
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyDeviceIdKey)
        }
    }
    
    private static var notiflyIsRegisteredAPNsKey: String = "notifly_isRegisteredAPNs"
    static var isRegisteredAPNsInUserDefaults: Bool? {
        set {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return
            }
            if let value = newValue {
                shared.set(value, forKey: notiflyIsRegisteredAPNsKey)
            } else {
                shared.removeObject(forKey: notiflyIsRegisteredAPNsKey)
            }
        }
        
        get {
            guard let shared = NotiflyCustomUserDefaults.notiflyUserDefaultsShared else {
                return nil
            }
            return shared.string(forKey: notiflyIsRegisteredAPNsKey) != nil
        }
    }
}
