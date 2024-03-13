//
//  SceneDelegate.swift
//  NotiflyTestApp
//
//  Created by Juyong Kim on 4/16/23.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else {
            return
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else {
            return
        }
        print("DeepLink: ", url)
        guard url.scheme == "pushnotiflyios", url.host == "navigation" else {
            return
        }
        let urlString = url.absoluteString
        guard urlString.contains("name") else {
            return
        }
        guard let components = URLComponents(string: url.absoluteString),
              let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        else {
            return
        }

        print("page이름 = \(name)")

        switch name {
        case "notification":
            let notificationVC = PushNotificationTestViewController()

            if let navigationController = window?.rootViewController as? UINavigationController {
                navigationController.pushViewController(notificationVC, animated: true)
            } else {
                let navigationController = UINavigationController(rootViewController: notificationVC)
                window?.rootViewController = navigationController
            }
        case "event":
            let trackingPageVC = TrackingTestViewController()

            if let navigationController = window?.rootViewController as? UINavigationController {
                navigationController.pushViewController(trackingPageVC, animated: true)
            } else {
                let navigationController = UINavigationController(rootViewController: trackingPageVC)
                window?.rootViewController = navigationController
            }
        case "user":
            let userPageVC = UserSettingsTestViewController()

            if let navigationController = window?.rootViewController as? UINavigationController {
                navigationController.pushViewController(userPageVC, animated: true)
            } else {
                let navigationController = UINavigationController(rootViewController: userPageVC)
                window?.rootViewController = navigationController
            }
        default:
            let mainVC = MainViewController()
            if let navigationController = window?.rootViewController as? UINavigationController {
                navigationController.pushViewController(mainVC, animated: true)
            } else {
                let navigationController = UINavigationController(rootViewController: mainVC)
                window?.rootViewController = navigationController
            }
        }
    }

}

