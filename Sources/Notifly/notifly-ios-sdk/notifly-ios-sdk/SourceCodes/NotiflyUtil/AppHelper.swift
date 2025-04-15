import Foundation
import Security
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

    static func getDeviceID() -> String? {
        if let deviceID = NotiflyCustomUserDefaults.deviceIdInUserDefaults {
            return deviceID
        } else if let deviceID = retrieveUniqueIdFromKeychain() as? String {
            NotiflyCustomUserDefaults.deviceIdInUserDefaults = deviceID
            return deviceID
        } else {
            guard let deviceUUID = UIDevice.current.identifierForVendor else {
                Logger.error("Failed to get the Device Identifier.")
                return nil
            }
            if saveUniqueIdToKeychain(deviceID: deviceUUID.notiflyStyleString) as Bool {
                NotiflyCustomUserDefaults.deviceIdInUserDefaults = deviceUUID.notiflyStyleString
            }
            return deviceUUID.notiflyStyleString
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

private func saveUniqueIdToKeychain(deviceID: String) -> Bool {
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
        let uniqueIdKey = "\(bundleIdentifier).notiflyUniqueDeviceId"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: uniqueIdKey,
            kSecValueData as String: deviceID.data(using: .utf8)!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
    }
    return false
}

private func retrieveUniqueIdFromKeychain() -> String? {
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
        let uniqueIdKey = "\(bundleIdentifier).notiflyUniqueDeviceId"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: uniqueIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
            let uniqueId = String(data: data, encoding: .utf8)
        {
            return uniqueId
        }
    }
    return nil
}
