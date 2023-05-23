//
//  Globals.swift
//  Daeseong Kim
//
//  Copyright © 2023 Michael At Work. All rights reserved.
//

import Foundation

public enum SdkType: String {
  case native
  case react_native
  case flutter
}

enum Globals {
  static var notiflySdkType: SdkType = .native

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

  private static var notiflyAPNsToken = "notifly_apnsToken"
  static var notiflyAPNsTokenInUserDefaults: Data? {
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: notiflyAPNsToken)
      } else {
        UserDefaults.standard.removeObject(forKey: notiflyAPNsToken)
      }
    }

    get {
      UserDefaults.standard.data(forKey: notiflyDeviceIdKey)
    }
  }

  private static var notiflyIsRegisteredAPNsKey: String = "notifly_isRegisteredAPNs"
  static var isRegisteredAPNsInUserDefaults: Bool? {
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: notiflyIsRegisteredAPNsKey)
      } else {
        UserDefaults.standard.removeObject(forKey: notiflyIsRegisteredAPNsKey)
      }
    }

    get {
      UserDefaults.standard.string(forKey: notiflyIsRegisteredAPNsKey) != nil
    }
  }
}
