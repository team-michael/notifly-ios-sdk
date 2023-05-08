//
//  Globals.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

final class Globals {

  private static var notiflyProjectIdKey = "notifly_projectId"
  static var projectIdInUserDefaults: String? {
    set {
      UserDefaults.standard.set(newValue, forKey: notiflyProjectIdKey)
    }

    get {
      UserDefaults.standard.string(forKey: notiflyProjectIdKey)
    }
  }

    private static var notiflyUserNameKey = "notifly_userName"
    static var userNameInUserDefaults: String? {
      set {
        UserDefaults.standard.set(newValue, forKey: notiflyUserNameKey)
      }

      get {
        UserDefaults.standard.string(forKey: notiflyUserNameKey)
      }
    }
    
    private static var notiflyPasswordKey = "notifly_password"
    static var passwordInUserDefaults: String? {
      set {
        UserDefaults.standard.set(newValue, forKey: notiflyPasswordKey)
      }

      get {
        UserDefaults.standard.string(forKey: notiflyPasswordKey)
      }
    }
    
    private static var notiflyExternalUserIdKey = "notifly_external_user_id"
    static var exteranlUserIdInUserDefaults: String? {
      set {
        UserDefaults.standard.set(newValue, forKey: notiflyExternalUserIdKey)
      }

      get {
        UserDefaults.standard.string(forKey: notiflyExternalUserIdKey)
      }
    }
    
    
    
  private static var notiflyDeviceIdKey = "notifly_deviceId"
  static var deviceIdInUserDefaults: String? {
    set {
      UserDefaults.standard.set(newValue, forKey: notiflyDeviceIdKey)
    }

    get {
      UserDefaults.standard.string(forKey: notiflyDeviceIdKey)
    }
  }

}
