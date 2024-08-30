import Firebase
import UIKit
import UserNotifications
import notifly_ios_sdk

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, error in
            if let error = error {
                print("Failed to request authorization: \(error)")
                return
            } else {
                guard granted else {
                    print("Notification permission denied.")
                    return
                }
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        FirebaseApp.configure()

        Notifly.initialize(
            projectId: TestConstant.projectID, username: TestConstant.username,
            password: TestConstant.password)
        Notifly.setUserId(userId: "test_ios_user_id")
        Notifly.setUserProperties(userProperties: [
            "sk": nil,
            "abc": true,
            "sdf": "a",
            "b": ["b": 1, "c": false],
            "kkk": [true, "ssss", 0, [123, "abc"]]
        ])
        Notifly.trackEvent(
            eventName: "View_Home",
            eventParams: [
                "sk": nil,
                "abc": true,
                "sdf": "a",
                "b": ["b": 1, "c": false],
                "kkk": [true, "ssss", 0, [123, "abc"]]
            ],
            segmentationEventParamKeys: ["sk"])

        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Notifly.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Notifly.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: () -> Void
    ) {
        Notifly.userNotificationCenter(
            notificationCenter,
            didReceive: response)
        completion()
    }

    func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void
    ) {
        Notifly.userNotificationCenter(
            notificationCenter,
            willPresent: notification,
            withCompletionHandler: completion)
    }
}
