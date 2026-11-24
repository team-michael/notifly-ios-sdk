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

    /// Reads on the caller; a cache miss or pending storage operation may block this thread.
    static func getDeviceID() -> String? {
        NotiflyStore.deviceID
    }

    static func makeNewDeviceID() -> String? {
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

}
