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
            Logger.error("FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize.")
            return
        }

        main = Notifly(
            projectID: projectID,
            username: username,
            password: password
        )
        
        if !isInitialized {
            Logger.error("Fail to Initialize`.")
            return
        }

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
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.application(application,
                                              didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    static func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.application(application,
                                              didFailToRegisterForRemoteNotificationsWithError: error)
    }

    static func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.application(application,
                                              didReceiveRemoteNotification: userInfo,
                                              fetchCompletionHandler: completionHandler)
    }

    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void)
    {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         didReceive: response,
                                                         withCompletionHandler: completion)
    }

    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         willPresent: notification,
                                                         withCompletionHandler: completion)
    }

    // MARK: - On-demand APIs

    static func trackEvent(eventName: String,
                           eventParams: [String: Any]? = nil,
                           segmentationEventParamKeys: [String]? = nil)
    {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.trackingManager.track(eventName: eventName,
                                   eventParams: eventParams,
                                   isInternal: false,
                                   segmentationEventParamKeys: segmentationEventParamKeys)
    }

    static func setUserId(userId: String? = nil) {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.userManager.setExternalUserId(userId)
    }

    static func setUserProperties(userProperties: [String: Any]) {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.userManager.setUserProperties(userProperties)
    }

    static func schedulePushNotification(title: String?,
                                         body: String?,
                                         url: URL,
                                         delay: TimeInterval)
    {
        if !isInitialized {
            Logger.error("You must call `Notifly.initialize` before calling this method.")
            return
        }
        main.notificationsManager.schedulePushNotification(title: title,
                                                           body: body,
                                                           url: url,
                                                           delay: delay)
    }
}
