import Foundation
import UIKit

class AppHelper {
    
    static func present(_ vc: UIViewController, animated: Bool = true) {
        if let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
           let topVC = window.topMostViewController {
            topVC.present(vc, animated: animated)
        }
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
