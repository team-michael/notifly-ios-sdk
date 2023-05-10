import notifly_ios_sdk
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        Notifly.initialize(projectID: TestConstant.projectID, username: TestConstant.username, password: TestConstant.password, useCustomClickHandler: false)
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
        }

        Notifly.initialize(launchOptions, projectID: "b80c3f0e2fbd5eb986df4f1d32ea2871", username: "minyong", password: "000000", useCustomClickHandler: false)
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
}
