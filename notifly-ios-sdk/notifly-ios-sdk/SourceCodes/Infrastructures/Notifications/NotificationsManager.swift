import Combine
import Foundation
import UIKit
import UserNotifications

class NotificationsManager: NSObject {
    
    // MARK: Properties
    
    private(set) var apnDeviceToken: Future<Data, Error>?
    
    private var apnDeviceTokenPromise: Future<Data, Error>.Promise?
    
    // MARK: Lifecycle
    
    override init() {
        super.init()
        setup()
    }
    
    // MARK: Instance Methods
    
    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        apnDeviceTokenPromise?(.success(deviceToken))
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        apnDeviceTokenPromise?(.failure(error))
    }
    
    // MARK: Private Methods
    
    private func setup() {
        // Setup observer to listen for APN Device tokens.
        apnDeviceToken = Future { [weak self] promise in
            self?.apnDeviceTokenPromise = promise
        }
        
        // Register Remote Notification.
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        // Observe notifications.
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func handleNotifcation(_ notification: UNNotification, completion: () -> Void) {
        let userInfo = notification.request.content.userInfo
        if let payload = userInfo["data"] {
            // TODO: Handle Notification
        }
        completion()
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void) {
        handleNotifcation(response.notification,
                          completion: completion)
    }
    
    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void) {
        handleNotifcation(notification) {
            completion(UNNotificationPresentationOptions())
        }
    }
}
