//
//  Globals.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

final class Globals {
  private static var notiflyAuthTokenKey = "notifly_authToken"
  static var authTokenInUserDefaults: String? {
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: notiflyAuthTokenKey)
      } else {
        UserDefaults.standard.removeObject(forKey: notiflyAuthTokenKey)
      }
    }

    get {
      UserDefaults.standard.string(forKey: notiflyAuthTokenKey)
    }
  }

  private static var notiflyExternalUserIdKey = "notifly_external_user_id"
  static var externalUserIdInUserDefaults: String? {
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: notiflyExternalUserIdKey)
      } else {
        UserDefaults.standard.removeObject(forKey: notiflyExternalUserIdKey)
      }
    }

    get {
      UserDefaults.standard.string(forKey: notiflyExternalUserIdKey)
    }
  }

  private static var notiflyDeviceIdKey = "notifly_deviceId"
  static var deviceIdInUserDefaults: String? {
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: notiflyDeviceIdKey)
      } else {
        UserDefaults.standard.removeObject(forKey: notiflyDeviceIdKey)
      }
    }

    get {
      UserDefaults.standard.string(forKey: notiflyDeviceIdKey)
    }
  }
}
