import UIKit

@available(iOSApplicationExtension, unavailable)
enum WebViewModalPresentation {

    static func topMostViewController(in window: UIWindow) -> UIViewController? {
        window.rootViewController?.topMostViewController
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
            if let selected = tab.selectedViewController {
                return selected.topMostViewController
            }
        }
        return self
    }
}
