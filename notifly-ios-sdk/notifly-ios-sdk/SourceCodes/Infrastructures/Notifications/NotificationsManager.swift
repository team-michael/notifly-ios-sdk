import Combine
import FirebaseMessaging
import Foundation
import SafariServices
import UIKit
import UserNotifications

class NotificationsManager: NSObject {
    // MARK: Properties

    /**
        // TODO: Remove  this workaround ocne push token can be succesfully retrieved.
     */
    private var _apnDeviceTokenPub: AnyPublisher<String, Error>?

    private(set) var apnDeviceTokenPub: AnyPublisher<String, Error>? {
        // TODO: Remove this temp workaround once APNs token is available.
        get {
            if let pub = _apnDeviceTokenPub {
                return pub
                    .catch { error in
                        Logger.info("Failed to get APNs Token with error: \(error)\n\nVisit \(#filePath) to replace this workaround once APNs can be successfully retrieved.\nAs workaround, debug APN Token is used.")
                        return Just("debug-apns-device-token").setFailureType(to: Error.self)
                    }
                    .eraseToAnyPublisher()
            } else {
                return nil
            }
        }
        set {
            _apnDeviceTokenPub = newValue
        }
    }

    var apnDeviceTokenPromise: Future<String, Error>.Promise?

    // MARK: Lifecycle

    override init() {
        super.init()
        setup()
    }

    // MARK: Instance Methods

    func application(_: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        Logger.info("Successfully received the push notification deviceToken: \(deviceToken)")
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error = error {
                Logger.info("Error fetching FCM registration token: \(error)")
            } else if let token = token {
                self.apnDeviceTokenPromise?(.success(token))
            }
        }
    }

    func application(_: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        Logger.error("Failed to receive the push notification deviceToken with error: \(error)")
        apnDeviceTokenPromise?(.failure(error))
    }

    func schedulePushNotification(title: String?,
                                  body: String?,
                                  url: URL,
                                  delay: TimeInterval)
    {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                Logger.error("Error requesting authorization for notifications: \(error.localizedDescription)")
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
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            // Schedule the notification
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    Logger.info("Notification scheduled successfully.")
                }
            }
        }
    }

    // MARK: Private Methods

    private func setup() {
        // Setup observer to listen for APN Device tokens.
        apnDeviceTokenPub = Future { [weak self] promise in
            self?.apnDeviceTokenPromise = promise
        }.eraseToAnyPublisher()

        // Register Remote Notification.
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleNotificationClick(_ notification: UNNotification, clickStatus: String, completion: () -> Void) {
        let pushData = notification.request.content.userInfo
        Logger.info("Received Push Notificatiob with data: \(pushData)")

        if let campaignID = pushData["campaign_id"] as? String {
            let messageID = pushData["notifly_message_id"] ?? "" as String
            if let pushClickEventParams = [
                "type": "message_event",
                "channel": "push-notification",
                "campaign_id": campaignID,
                "notifly_message_id": messageID,
                "click_status": clickStatus,
            ] as? [String: Any] {
                Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.pushClickEventName, params: pushClickEventParams)
            }
        }

        if let urlString = pushData["url"] as? String,
           let url = URL(string: urlString)
        {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        UIApplication.shared.applicationIconBadgeNumber = 0
        completion()
    }

    private func presentWebViewForURL(url: URL) {
        let browserVC = SFSafariViewController(url: url)
        AppHelper.present(browserVC) {
            Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.pushNotificationMessageShown, params: nil)
        }
    }

    private func stringFromPushToken(data: Data) -> String {
        return data.map { String(format: "%.2hhx", $0) }.joined()
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(_: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void)
    {
        let clickStatus = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        handleNotificationClick(response.notification,
                                clickStatus: clickStatus,
                                completion: completion)
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(_: UNUserNotificationCenter,
                                       willPresent _: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        // handleNotificationClick(notification) {
        completion([.banner, .badge, .sound])
        // }
    }
}
