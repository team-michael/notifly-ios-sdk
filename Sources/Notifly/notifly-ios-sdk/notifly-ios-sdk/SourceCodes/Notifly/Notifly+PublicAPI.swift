import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/**
 Contains all available Notifly SDK Public APIs.
 */
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {
    static func initialize(
        projectId: String,
        username: String,
        password: String
    ) {
        guard FirebaseApp.app() != nil else {
            Logger.error("FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize.")
            return
        }

        if !NotiflyHelper.testRegex(projectId, regex: NotiflyConstant.projectIdRegex) {
            Logger.error("Invalid Project ID. Please provide a valid Project ID.")
            return
        }

        Notifly(
            projectId: projectId,
            username: username,
            password: password
        )

        guard let main = try? Notifly.main else {
            Logger.error("Failed to initialize Notifly.")
            return
        }

        if let pushData = Notifly.coldStartNotificationData {
            let clickStatus = "background"
            if let urlString = pushData["url"] as? String,
               let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    main.notificationsManager.logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
                }
            } else {
                main.notificationsManager.logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
            }
            Notifly.coldStartNotificationData = nil
        }
        main.inAppMessageManager.userStateManager.syncState(postProcessConfig:
            PostProcessConfigForSyncState(merge: false, clear: false))
        Messaging.messaging().token { token, error in
            if let token = token,
               error == nil
            {
                try? main.notificationsManager.deviceTokenPromise?(.success(token))
                main.notificationsManager.setDeviceTokenPub(token: token)
            }
            try? main.trackingManager.trackSessionStartInternalEvent()
            Logger.info("📡 Notifly SDK is successfully initialized.")
        }
    }

    static func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        guard (try? main) != nil else {
            Messaging.messaging().apnsToken = deviceToken
            return
        }
        try? main.notificationsManager.application(application,
                                                   didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    static func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        guard (try? main) != nil else {
            Logger.error("Failed to Register for Remote Notifications: However, you can track events and set user properties without registering for remote notifications.")
            return
        }
        try? main.notificationsManager.application(application,
                                                   didFailToRegisterForRemoteNotificationsWithError: error)
    }

    static func application(_: UIApplication, didReceiveRemoteNotification _: [AnyHashable: Any]) {
        Logger.error("Deprecated Method.")
    }

    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
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

    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
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

    static func trackEvent(eventName: String,
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

    static func setUserId(userId: String? = nil) {
        guard let main = try? main else {
            if userId != nil {
                Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId.")
            } else {
                Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId to unregister user id.")
            }
            return
        }
        try? main.userManager.setExternalUserId(userId)
    }

    static func setUserProperties(userProperties: [String: Any]) {
        guard let main = try? main else {
            Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserProperties.")
            return
        }
        try? main.userManager.setUserProperties(userProperties)
    }

    static func setSdkType(type: String) {
        if let sdkType = SdkWrapperType(rawValue: type) {
            Notifly.sdkWrapperType = sdkType
            Logger.info("Notifly SDK type has been set to \(sdkType.rawValue).")
        } else {
            Logger.error("Notifly SDK type is invalid. Please set type to one of the following: 'react_native', 'flutter'")
        }
    }

    static func setSdkVersion(version: String) {
        Notifly.sdkWrapperVersion = version
    }

    static func disableInAppMessage() {
        Notifly.inAppMessageDisabled = true
        Logger.info("In App Message Channel is disabled.")
    }

    static func schedulePushNotification(title: String?,
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

    static func registerFCMToken(token: String?) {
        guard let main = try? main else {
            Logger.error("Notifly is not initialized. Please call Notifly.initialize before calling Notifly.registerFCMToken.")
            return
        }
        guard let token = token else {
            Logger.error("Token must not be empty.")
            return
        }
        try? main.notificationsManager.registerFCMToken(token: token)
        Logger.info("FCM token is successfully registered.")
    }
}
