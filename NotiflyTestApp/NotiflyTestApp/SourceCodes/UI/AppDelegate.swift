import Firebase
import notifly_ios_sdk
import UIKit
import UserNotifications

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

        Notifly.addInAppMessageEventListener { eventName, eventParams in
            print("In App Message Event: \(eventName)")
            if let params = eventParams {
                print("In App Message Event Params: \(params)")
            }
        }

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
