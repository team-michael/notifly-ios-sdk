import Foundation
import Security
import UIKit

class AppHelper {
    static func present(_ vc: UIViewController, animated: Bool = true, completion: (() -> Void)?) {
        if let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
           let topVC = window.topMostViewController
        {
            topVC.present(vc, animated: animated, completion: completion)
        }
    }

    static func getDeviceID() throws -> String {
        if let deviceID = Globals.deviceIdInUserDefaults {
            return deviceID
        } else if let deviceID = retrieveUniqueIdFromKeychain() as? String {
            Globals.deviceIdInUserDefaults = deviceID
            return deviceID
        } else {
            guard let deviceUUID = UIDevice.current.identifierForVendor else {
                throw NotiflyError.unexpectedNil("Failed to get the Device Identifier.")
            }
            if saveUniqueIdToKeychain(deviceID: deviceUUID.notiflyStyleString) as Bool {
                Globals.deviceIdInUserDefaults = deviceUUID.notiflyStyleString
            }
            return deviceUUID.notiflyStyleString
        }
    }

    static func getAppVersion() throws -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw NotiflyError.unexpectedNil("Failed to get the App version.")
        }
        return version
    }

    static func getSDKVersion() throws -> String {
        guard let version = Bundle(for: Notifly.self).infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw NotiflyError.unexpectedNil("Failed to get the SDK version.")
        }
        return version
    }

    static func getDevicePlatform() -> String {
        return UIDevice.current.systemName.lowercased()
    }

    static func getiOSVersion() -> String {
        return UIDevice.current.systemVersion
    }
}

private extension UIWindow {
    var topMostViewController: UIViewController? {
        return rootViewController?.topMostViewController
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMostViewController ?? nav
        }
        if let tab = self as? UITabBarController {
            return (tab.selectedViewController ?? self).topMostViewController
        }
        return self
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
            print("Unique ID saved to Keychain")
            return true
        } else {
            print("Failed to save Unique ID to Keychain")
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
