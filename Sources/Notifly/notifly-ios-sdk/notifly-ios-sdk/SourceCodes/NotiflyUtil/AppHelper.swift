import Foundation
import UIKit

class AppHelper {
    static func getNotiflyDeviceID() -> String? {
        guard let deviceID = AppHelper.getDeviceID() else {
            return nil
        }
        return UUID(
            name: deviceID,
            namespace: TrackingConstant.HashNamespace.deviceID
        ).notiflyStyleString
    }

    /// Cache misses read Keychain synchronously and may delay the calling thread.
    static func getDeviceID() -> String? {
        NotiflyCustomUserDefaults.deviceIdInUserDefaults
    }

    // Capture at registration; use only if Keychain and UserDefaults have no device ID.
    static func makeNewDeviceID() -> String? {
        // Capture UIKit data before acquiring storage locks; Keychain never switches threads.
        if Thread.isMainThread {
            return UIDevice.current.identifierForVendor?.notiflyStyleString
        }
        return DispatchQueue.main.sync {
            UIDevice.current.identifierForVendor?.notiflyStyleString
        }
    }

    static func getCurrentTimestamp(unit: TimeConstant.TimestampUnit = .microsecond) -> Int {
        return Int(Date().timeIntervalSince1970 * Double(unit.rawValue))
    }

    static func getAppVersion() -> String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else {
            Logger.error("Failed to get the App version.")
            return nil
        }
        return version
    }

    static func getDevicePlatform() -> String {
        return NotiflyConstant.iosPlatform
    }

    static func getiOSVersion() -> String {
        return UIDevice.current.systemVersion
    }

    static func getBundleIdentifier() -> String? {
        return Bundle.main.bundleIdentifier
    }

}
