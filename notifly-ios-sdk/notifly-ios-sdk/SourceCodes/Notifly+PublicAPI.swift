import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit


/**
 Contains all available Notifly SDK Public APIs.
 */
public extension Notifly {
    // MARK: - Required Setup API configurations

    /**
     Initializes the Notifly SDK. This method is to be called as soon as the app laucnhes. (AppDelegate.applicationDidFinishLaunching)
     */

    static func initialize(
        projectID: String,
        username: String,
        password: String
    ) {
        guard FirebaseApp.app() != nil else {
            fatalError("🔥 FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize.")
        }
        
        main = Notifly(
            projectID: projectID,
            username: username,
            password: password
        )

        Messaging.messaging().token { token, error in
            if let token = token,
               error == nil
            {
                main.notificationsManager.apnDeviceTokenPromise?(.success(token))
            }
        }
        main.trackingManager.trackSessionStartInternalEvent()
    }

    static func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        main.notificationsManager.application(application,
                                              didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    static func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        main.notificationsManager.application(application,
                                              didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    static func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        main.notificationsManager.application(application,
                                              didReceiveRemoteNotification: userInfo,
                                              fetchCompletionHandler: completionHandler)
    }
    
    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void)
    {
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         didReceive: response,
                                                         withCompletionHandler: completion)
    }

    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         willPresent: notification,
                                                         withCompletionHandler: completion)
    }

    // MARK: - On-demand APIs

    static func trackEvent(name: String,
                           params: [String: Any]? = nil,
                           segmentationEventParamKeys: [String]? = nil)
    {
        main.trackingManager.track(eventName: name,
                                   isInternal: false,
                                   params: params,
                                   segmentationEventParamKeys: segmentationEventParamKeys)
    }

    static func setUserID(_ userID: String? = nil) throws {
        try main.userManager.setExternalUserID(userID)
    }

    static func setUserProperties(_ properties: [String: Any]) throws {
        try main.userManager.setUserProperties(properties)
    }

    static func schedulePushNotification(title: String?,
                                         body: String?,
                                         url: URL,
                                         delay: TimeInterval)
    {
        main.notificationsManager.schedulePushNotification(title: title,
                                                           body: body,
                                                           url: url,
                                                           delay: delay)
    }
}
