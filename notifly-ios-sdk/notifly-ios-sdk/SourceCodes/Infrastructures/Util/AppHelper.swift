import Foundation
import UIKit

class AppHelper {
    
    static func present(_ vc: UIViewController, animated: Bool = true, completion: (() -> Void)?) {
        if let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
           let topVC = window.topMostViewController {
            topVC.present(vc, animated: animated, completion: completion)
        }
    }
    
    static func getDeviceID() throws -> String {
        guard let deviceUUID = UIDevice.current.identifierForVendor else {
            throw NotiflyError.unexpectedNil("Failed to get the Device Identifier.")
        }
        return deviceUUID.notiflyStyleString
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
        return UIDevice.current.systemName
    }
    
    static func getiOSVersion() -> String {
        return UIDevice.current.systemVersion
    }
}


private extension UIWindow {
    var topMostViewController: UIViewController? {
        return self.rootViewController?.topMostViewController
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
