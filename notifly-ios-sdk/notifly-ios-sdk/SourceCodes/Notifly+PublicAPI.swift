import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/**
 Contains all available Notifly SDK Public APIs.
 */
@objc public extension Notifly {
    // MARK: - Required Setup API configurations

    /**
     Initializes the Notifly SDK. This method is to be called as soon as the app laucnhes. (AppDelegate.applicationDidFinishLaunching)
     */

    @objc static func initialize(
        projectId: String,
        username: String,
        password: String
    ) {
        guard FirebaseApp.app() != nil else {
            Logger.error("FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize.")
            return
        }

        _main = Notifly(
            projectID: projectId,
            username: username,
            password: password
        )

        guard let main = _main else {
            Logger.error("Failed to initialize Notifly.")
            return
        }

        Messaging.messaging().token { token, error in
            if let token = token,
               error == nil
            {
                try? main.notificationsManager.deviceTokenPromise?(.success(token))
            }
        }

        try? main.trackingManager.trackSessionStartInternalEvent()
        Logger.info("📡 Notifly SDK is successfully initialized.")
    }

    @objc static func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        guard (try? main) != nil else {
            Messaging.messaging().apnsToken = deviceToken
            return
        }
        try? main.notificationsManager.application(application,
                                                   didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    @objc static func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        guard (try? main) != nil else {
            Logger.error("Failed to Register for Remote Notifications: However, you can track events and set user properties without registering for remote notifications.")
            return
        }
        try? main.notificationsManager.application(application,
                                                   didFailToRegisterForRemoteNotificationsWithError: error)
    }

    @objc static func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        if let notiflyMessageType = userInfo["notifly_message_type"] as? String,
           notiflyMessageType == "in-app-message"
        {
            guard (try? main) != nil else {
                Logger.error("Fail to Received In-App Message: Notifly is not initialized yet.")
                return
            }
            try? main.notificationsManager.handleDataMessage(didReceiveRemoteNotification: userInfo)
        }
    }

    @objc static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse)
    {
        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]?,
           let clickStatus = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        {
            guard let notiflyMessageType = pushData["notifly_message_type"] as? String,
                  notiflyMessageType == "push-notification"
            else {
                return
            }
            guard (try? main) != nil else {
                Notifly.coldStartNotificationData = pushData
                return
            }

            try? main.notificationsManager.userNotificationCenter(notificationCenter,
                                                                  didReceive: response)
        }
    }

    @objc static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        if let pushData = notification.request.content.userInfo as [AnyHashable: Any]?,
           let notiflyMessageType = pushData["notifly_message_type"] as? String,
           notiflyMessageType == "push-notification"
        {
            guard (try? main) != nil else {
                Logger.error("Fail to Show Notifly Foreground Message: Notifly is not initialized yet.")
                return
            }

            try? main.notificationsManager.userNotificationCenter(notificationCenter,
                                                                  willPresent: notification,
                                                                  withCompletionHandler: completion)
        }
    }

    // MARK: - On-demand APIs

    @objc static func trackEvent(eventName: String,
                           eventParams: [String: Any]? = nil,
                           segmentationEventParamKeys: [String]? = nil)
    {
        guard let main = try? main else {
            Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.trackEvent.")
            return
        }
        try? main.trackingManager.track(eventName: eventName,
                                        eventParams: eventParams,
                                        isInternal: false,
                                        segmentationEventParamKeys: segmentationEventParamKeys)
    }

    @objc static func setUserId(userId: String? = nil) {
        guard let main = try? main else {
            if let userId = userId {
                Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId.")
            } else {
                Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId to unregister user id.")
            }
            return
        }
        try? main.userManager.setExternalUserId(userId)
    }

    @objc static func setUserProperties(userProperties: [String: Any]) {
        guard let main = try? main else {
            Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserProperties.")
            return
        }
        try? main.userManager.setUserProperties(userProperties)
    }

    @objc static func setSdkType(type: String) {
        if let sdkType = SdkType(rawValue: type) {
            Notifly.sdkType = sdkType
            Logger.info("Notifly SDK type is set to \(sdkType.rawValue).")
        } else {
            Logger.error("Notifly SDK type is invalid. Please set Notifly.sdkType to one of the following: react_native, flutter, native (default)")
        }
    }

    @objc static func setSdkVersion(version: String) {
        Notifly.sdkVersion = version
    }

    @objc static func schedulePushNotification(title: String?,
                                         body: String?,
                                         url: URL,
                                         delay: TimeInterval)
    {
        guard let main = try? main else {
            Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.schedulePushNotification.")
            return
        }
        try? main.notificationsManager.schedulePushNotification(title: title,
                                                                body: body,
                                                                url: url,
                                                                delay: delay)
    }
}
