import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// Contains all available Notifly SDK Public APIs.
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {
    static func initialize(
        projectId: String,
        username: String,
        password: String
    ) {
        guard FirebaseApp.app() != nil else {
            Logger.error(
                "FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize."
            )
            return
        }

        if !NotiflyHelper.testRegex(projectId, regex: NotiflyConstant.projectIdRegex) {
            Logger.error("Invalid Project ID. Please provide a valid Project ID.")
            return
        }

        Notifly.setup(
            projectId: projectId,
            username: username,
            password: password
        )

        guard let main = try? Notifly.main else {
            Logger.error("Failed to initialize Notifly.")
            return
        }

        Notifly.asyncWorker.addTask {
            main.inAppMessageManager.userStateManager.syncState(
                postProcessConfig:
                    PostProcessConfigForSyncState(merge: false, clear: false),
                handleExternalUserIdMismatch: true
            ) {
                Notifly.asyncWorker.unlock()
            }
        }

        if let pushData = Notifly.coldStartNotificationData {
            let clickStatus = "background"
            if let urlString = pushData["url"] as? String,
                let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    main.trackingManager.trackPushClickInternalEvent(
                        pushData: pushData,
                        clickStatus: clickStatus
                    )
                }
            } else {
                main.trackingManager.trackPushClickInternalEvent(
                    pushData: pushData,
                    clickStatus: clickStatus
                )
            }
            Notifly.coldStartNotificationData = nil
        }

        // NotificationsManager now handles all token acquisition logic
        Notifly.asyncWorker.addTask {
            main.trackingManager.trackSessionStartInternalEvent()
            Logger.info("📡 Notifly SDK is successfully initialized.")
        }
    }

    static func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let main = try? main else {
            Messaging.messaging().apnsToken = deviceToken
            return
        }
        main.notificationsManager.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
    }

    static func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard let main = try? main else {
            Logger.error(
                "Failed to Register for Remote Notifications: However, you can track events and set user properties without registering for remote notifications."
            )
            return
        }
        main.notificationsManager.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
    }

    static func application(
        _: UIApplication,
        didReceiveRemoteNotification _: [AnyHashable: Any]
    ) {
        Logger.error("Deprecated Method.")
    }

    static func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) {
        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]?,
            let clickStatus = UIApplication.shared.applicationState == .active
                ? "foreground" : "background"
        {
            guard let notiflyMessageType = pushData["notifly_message_type"] as? String,
                notiflyMessageType == "push-notification"
            else {
                return
            }
            guard let main = try? main else {
                Notifly.coldStartNotificationData = pushData
                return
            }

            main.notificationsManager.userNotificationCenter(
                notificationCenter,
                didReceive: response
            )
        }
    }

    static func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void
    ) {
        if let pushData = notification.request.content.userInfo as [AnyHashable: Any]?,
            let notiflyMessageType = pushData["notifly_message_type"] as? String,
            notiflyMessageType == "push-notification"
        {
            guard let main = try? main else {
                Logger.error(
                    "Fail to Show Notifly Foreground Message: Notifly is not initialized yet."
                )
                return
            }

            main.notificationsManager.userNotificationCenter(
                notificationCenter,
                willPresent: notification,
                withCompletionHandler: completion
            )
        }
    }

    static func trackEvent(
        eventName: String,
        eventParams: [String: Any]? = nil,
        segmentationEventParamKeys: [String]? = nil
    ) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.trackEvent."
            )
            return
        }
        main.trackingManager.track(
            eventName: eventName,
            eventParams: eventParams,
            isInternal: false,
            segmentationEventParamKeys: segmentationEventParamKeys
        )
    }

    static func setUserId(userId: String? = nil) {
        guard let main = try? main else {
            if userId != nil {
                Logger.error(
                    "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId."
                )
            } else {
                Logger.error(
                    "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId to unregister user id."
                )
            }
            return
        }
        main.userManager.setExternalUserId(userId)
    }

    static func getNotiflyUserId() -> String? {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.getNotiflyUserId."
            )
            return nil
        }
        return try? main.userManager.getNotiflyUserID()
    }

    static func setUserProperties(userProperties: [String: Any]) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserProperties."
            )
            return
        }

        if userProperties.isEmpty {
            Logger.info(
                "Empty dictionary provided for setting user properties. Ignoring this call."
            )
            return
        }

        if let timezone = userProperties[TrackingConstant.InternalUserPropertyKey.timezone]
            as? String
        {
            if !TimezoneUtil.isValidTimezoneId(timezone) {
                Logger.info(
                    "Invalid timezone ID \(timezone). Please check your timezone ID. Omitting timezone property."
                )
                var newUserProperties = userProperties
                newUserProperties.removeValue(
                    forKey: TrackingConstant.InternalUserPropertyKey.timezone
                )
                return setUserProperties(userProperties: newUserProperties)
            }
        }

        main.userManager.setUserProperties(userProperties: userProperties)
    }

    static func setPhoneNumber(_ phoneNumber: String) {
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.phoneNumber: phoneNumber
        ])
    }

    static func setEmail(_ email: String) {
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.email: email
        ])
    }

    static func setTimezone(_ timezone: String) {
        if !TimezoneUtil.isValidTimezoneId(timezone) {
            Logger.info("Invalid timezone ID \(timezone). Please check your timezone ID.")
            return
        }
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.timezone: timezone
        ])
    }

    static func setSdkType(type: String) {
        if let sdkType = SdkWrapperType(rawValue: type) {
            NotiflySdkConfig.sdkWrapperType = sdkType
            Logger.info("Notifly SDK type has been set to \(sdkType.rawValue).")
        } else {
            Logger.error(
                "Notifly SDK type is invalid. Please set type to one of the following: 'react_native', 'flutter'"
            )
        }
    }

    static func setSdkVersion(version: String) {
        NotiflySdkConfig.sdkWrapperVersion = version
    }

    static func disableInAppMessage() {
        Notifly.inAppMessageDisabled = true
        Logger.info("In App Message Channel is disabled.")
    }

    static func schedulePushNotification(
        title: String?,
        body: String?,
        url: URL,
        delay: TimeInterval
    ) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.schedulePushNotification."
            )
            return
        }
        main.notificationsManager.schedulePushNotification(
            title: title,
            body: body,
            url: url,
            delay: delay
        )
    }

    static func registerFCMToken(token: String?) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.registerFCMToken."
            )
            return
        }
        guard let token = token else {
            Logger.error("Token must not be empty.")
            return
        }
        main.notificationsManager.registerFCMToken(token: token)
        Logger.info("FCM token is successfully registered.")
    }

    static func addInAppMessageEventListener(listener: @escaping InAppMessageEventListener) {
        guard let main = try? main else { return }
        main.inAppMessageManager.addEventListener(listener)
    }

    static func removeAllInAppMessageEventListener() {
        guard let main = try? main else { return }
        main.inAppMessageManager.removeAllEventListeners()
    }
}
