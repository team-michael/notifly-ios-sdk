import notifly_ios_sdk
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // TODO: remove this code after testing. this section is only for testing.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
           if let error = error {
                // 권한 요청 중 에러가 발생한 경우 처리
                print("Failed to request authorization: \(error)")
            } else {
                // 권한 요청이 성공한 경우 처리
                print("Authorization granted: \(granted)")
            }
        }
        return true
    }
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Notifly.application(application,
                            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Notifly.application(application,
                            didFailToRegisterForRemoteNotificationsWithError: error)
    }
}
