import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// Integrates remote and local notifications with Notifly.
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {

    /// Forwards successful APNs registration to Notifly and Firebase Messaging.
    ///
    /// Call this from the matching application-delegate callback. When Notifly is
    /// initialized, it associates the APNs token with Firebase and starts FCM token
    /// acquisition. Before initialization, it only assigns the token to Firebase.
    ///
    /// - Parameters:
    ///   - application: The application passed to the application-delegate callback.
    ///   - deviceToken: The unmodified APNs device-token data supplied by iOS.
    /// - Note: Token acquisition and registration continue asynchronously. This method
    ///   does not provide a completion callback or return an FCM token.
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

    /// Forwards an APNs registration failure to Notifly.
    ///
    /// Call this from the matching application-delegate callback so the SDK can handle
    /// the registration failure. Before initialization, this method only logs a message.
    /// Event tracking and user-property APIs remain available without a push token.
    ///
    /// - Parameters:
    ///   - application: The application passed to the application-delegate callback.
    ///   - error: The original APNs registration error supplied by iOS.
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

    /// Handles the legacy remote-notification forwarding entry point.
    ///
    /// This compatibility method only logs that it is deprecated. It does not process
    /// the payload, open a link, or track delivery. Use the appropriate
    /// `userNotificationCenter` forwarding method for presentation and user responses.
    ///
    /// - Parameters:
    ///   - application: The host application. This argument is ignored.
    ///   - userInfo: The remote-notification payload. This argument is ignored.
    static func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) {
        Logger.error("Deprecated Method.")
    }

    /// Handles a user's interaction with a Notifly push notification.
    ///
    /// Forward this call from the notification-center delegate's response callback.
    /// Only payloads whose `notifly_message_type` is `push-notification` are handled.
    /// If initialization has not completed, the response payload and action identifier
    /// are retained for processing during initialization. Otherwise, the SDK opens the
    /// applicable link and tracks the interaction as appropriate for the action.
    ///
    /// - Parameters:
    ///   - notificationCenter: The notification center delivering the response.
    ///   - response: The notification and selected action supplied by iOS.
    /// - Important: This method does not receive or invoke the system delegate's
    ///   completion handler. The host application must complete that callback itself.
    static func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) {
        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]? {
            guard let notiflyMessageType = pushData["notifly_message_type"] as? String,
                notiflyMessageType == "push-notification"
            else {
                return
            }
            guard let main = try? main else {
                Notifly.coldStartNotificationData = pushData
                Notifly.coldStartNotificationActionIdentifier = response.actionIdentifier
                return
            }

            main.notificationsManager.userNotificationCenter(
                notificationCenter,
                didReceive: response
            )
        }
    }

    /// Supplies foreground presentation options for a Notifly push notification.
    ///
    /// Forward this call from the matching notification-center delegate callback after
    /// initializing the SDK. For a recognized Notifly push, the completion closure is
    /// called synchronously with banner, badge, sound, and notification-list options.
    ///
    /// - Parameters:
    ///   - notificationCenter: The notification center presenting the notification.
    ///   - notification: The notification supplied by iOS. Its payload must contain
    ///     `notifly_message_type` with the value `push-notification` to be handled.
    ///   - completion: The closure that submits presentation options to iOS. It is
    ///     called on the calling thread for a handled notification.
    /// - Important: The closure is not called for unrelated notifications or before SDK
    ///   initialization. The host delegate must handle those paths and ensure that its
    ///   system completion handler is invoked exactly once.
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

    /// Requests notification permission and schedules a one-time local notification.
    ///
    /// Call after initialization. The SDK requests alert, sound, and badge authorization,
    /// then submits a local notification request. Permission-request and scheduling
    /// errors are logged; this method provides no delivery or completion callback.
    ///
    /// - Parameters:
    ///   - title: The notification title. If both title and body are `nil`, the title is
    ///     `Test Push Notification`; otherwise a missing title becomes an empty string.
    ///   - body: The notification body, or `nil` for an empty body.
    ///   - url: The URL stored under the notification payload's `url` key.
    ///   - delay: The delay in seconds passed to `UNTimeIntervalNotificationTrigger`.
    ///     Supply a positive interval; this method does not validate it.
    /// - Note: The payload contains the URL but does not add a Notifly message-type
    ///   marker. The host application is responsible for handling the local response.
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

    /// Registers an externally obtained Firebase Cloud Messaging token with Notifly.
    ///
    /// Call after initialization when an integration supplies its own FCM token. The
    /// token updates SDK token state and may queue a token-registration event. Returning
    /// does not confirm server delivery. A previously successful identical token avoids
    /// sending a duplicate token-change event.
    ///
    /// - Parameter token: The FCM registration-token string. `nil` is logged and ignored;
    ///   it does not clear an existing token. A non-`nil` string is passed through without
    ///   an additional empty-string or format check.
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
}
