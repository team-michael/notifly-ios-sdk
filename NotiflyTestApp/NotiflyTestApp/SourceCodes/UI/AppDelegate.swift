import Firebase
import notifly_ios_sdk
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication,
                     didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {

        FirebaseApp.configure()
        Notifly.initialize(projectID: TestConstant.projectID, username: TestConstant.username, password: TestConstant.password)
        UNUserNotificationCenter.current().delegate = self

        // TODO: remove this code after testing. this section is only for testing.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Failed to request authorization: \(error)")
            } else {
                print("Authorization granted: \(granted)")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            Notifly.trackEvent(eventName: "HIHI")
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        Notifly.application(application,
                            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        Notifly.application(application,
                            didFailToRegisterForRemoteNotificationsWithError: error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        Notifly.application(application,
                            didReceiveRemoteNotification: userInfo,
                            fetchCompletionHandler: completionHandler)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: () -> Void)
    {
        Notifly.userNotificationCenter(notificationCenter,
                                       didReceive: response,
                                       withCompletionHandler: completion)
    }

    func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        Notifly.userNotificationCenter(notificationCenter,
                                       willPresent: notification,
                                       withCompletionHandler: completion)
    }
}
