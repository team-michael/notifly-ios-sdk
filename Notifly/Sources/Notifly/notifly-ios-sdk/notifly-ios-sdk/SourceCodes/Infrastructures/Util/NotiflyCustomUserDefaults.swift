//
//  NotiflyCustomUserDefaults.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

enum NotiflyCustomUserDefaults {
    private static let notiflyUserDefaults = UserDefaults(suiteName: "tech.notifly") ?? UserDefaults.standard
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
