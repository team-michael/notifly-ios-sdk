import UIKit
import UserNotifications

@available(iOSApplicationExtension, unavailable)
extension NotificationsManager {

    func schedulePushNotification(
        title: String?,
        body: String?,
        url: URL,
        delay: TimeInterval
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                Logger.error(
                    "Error requesting authorization for notifications: \(error.localizedDescription)"
                )
                return
            }

            // Create a notification content object
            let content = UNMutableNotificationContent()
            content.title = title ?? (body == nil ? "Test Push Notification" : "")
            content.body = body ?? ""
            content.badge = 1 as NSNumber
            content.sound = .default
            content.userInfo["url"] = url.absoluteString

            // Create a trigger for the notification
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)

            // Create a request for the notification
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )

            // Schedule the notification
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error("Error scheduling notification: \(error.localizedDescription)")
                }
                else {
                    Logger.info("Notification scheduled successfully.")
                }
            }
        }
    }

    func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            if !(UIApplication.shared.isRegisteredForRemoteNotifications
                && NotiflyStore.isRegisteredAPNs == true)
            {
                Logger.info("📝 Registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
                NotiflyStore.isRegisteredAPNs = true
            }
            else {
                Logger.info("📝 Already registered for remote notifications, re-requesting...")
                // Force re-registration in case of retry
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Registers the unsubscribe action category for advertising push notifications.
    /// Merges the category with existing registrations to preserve the host app categories.
    func registerAdPushCategory() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            guard
                !existing.contains(where: {
                    $0.identifier == NotiflyConstant.AdPush.categoryIdentifier
                })
            else {
                return
            }

            let unsubscribeAction = UNNotificationAction(
                identifier: NotiflyConstant.AdPush.unsubscribeActionIdentifier,
                title: NotiflyConstant.AdPush.unsubscribeActionTitle,
                options: [.foreground]
            )
            let adCategory = UNNotificationCategory(
                identifier: NotiflyConstant.AdPush.categoryIdentifier,
                actions: [unsubscribeAction],
                intentIdentifiers: [],
                options: []
            )
            center.setNotificationCategories(existing.union([adCategory]))
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

@available(iOSApplicationExtension, unavailable)
extension NotificationsManager: UNUserNotificationCenterDelegate {

    /// Handles a response forwarded by the public API; the host completes the system callback.
    @nonobjc public func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) {
        // Open unsubscribe_url when the user selects the advertising push unsubscribe action.
        if response.actionIdentifier == NotiflyConstant.AdPush.unsubscribeActionIdentifier {
            if let urlString = response.notification.request.content.userInfo[
                NotiflyConstant.AdPush.unsubscribeUrlKey
            ] as? String,
                let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:])
            }
            return
        }

        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]?,
            let clickStatus = UIApplication.shared.applicationState == .active
                ? "foreground" : "background"
        {
            guard let notiflyMessageType = pushData["notifly_message_type"] as? String,
                notiflyMessageType == "push-notification"
            else {
                return
            }

            guard let main = try? Notifly.main else {
                Notifly.coldStartNotificationData = pushData
                return
            }

            if let urlString = pushData["url"] as? String,
                let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    main.trackingManager.trackPushClickInternalEvent(
                        pushData: pushData,
                        clickStatus: clickStatus
                    )
                }
            }
            else {
                main.trackingManager.trackPushClickInternalEvent(
                    pushData: pushData,
                    clickStatus: clickStatus
                )
            }
        }
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void
    ) {
        completion([.banner, .badge, .sound, .list])
    }
}
