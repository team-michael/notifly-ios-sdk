import Foundation
import Security
import UIKit

class AppHelper {
    static func getNotiflyDeviceID() -> String? {
        guard let deviceID = AppHelper.getDeviceID() else {
            return nil
        }
        return UUID(name: deviceID,
                    namespace: TrackingConstant.HashNamespace.deviceID).notiflyStyleString
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

    static func getAppVersion() -> String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            Logger.error("Failed to get the App version.")
            return nil
        }
        return version
    }

    static func getDevicePlatform() -> String {
        return "ios"
    }

    static func getiOSVersion() -> String {
        return UIDevice.current.systemVersion
    }

    static func getBundleIdentifier() -> String? {
        return Bundle.main.bundleIdentifier
    }

    static func makeJsonCodable(_ jsonData: [String: Any]?) -> [String: AnyCodable]? {
        guard let jsonData = jsonData else { return nil }
        return jsonData.mapValues { value in
            if let array = value as? [Any?] {
                return AnyCodable(array.compactMap { element in AppHelper.toCodableValue(element) })
            } else if let dictionary = value as? [String: Any] {
                return AnyCodable(makeJsonCodable(dictionary))
            }
            return AppHelper.toCodableValue(value)
        }
    }

    static func toCodableValue(_ value: Any?) -> AnyCodable {
        if let str = value as? String {
            return AnyCodable(str)
        } else if let int = value as? Int {
            return AnyCodable(int)
        } else if let double = value as? Double {
            return AnyCodable(double)
        } else if let float = value as? Float {
            return AnyCodable(float)
        } else if let bool = value as? Bool {
            return AnyCodable(bool)
        } else {
            return AnyCodable(value)
        }
    }
}

private func saveUniqueIdToKeychain(deviceID: String) -> Bool {
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
        let uniqueIdKey = "\(bundleIdentifier).notiflyUniqueDeviceId"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: uniqueIdKey,
            kSecValueData as String: deviceID.data(using: .utf8)!,
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
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let uniqueId = String(data: data, encoding: .utf8) {
            return uniqueId
        }
    }
    return nil
}
