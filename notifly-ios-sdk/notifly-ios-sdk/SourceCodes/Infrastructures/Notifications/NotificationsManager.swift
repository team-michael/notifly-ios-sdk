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
                        Logger.error("Failed to get APNs Token with error: \(error)\n\nVisit \(#filePath) to replace this workaround once APNs can be successfully retrieved.\nAs workaround, debug APN Token is used.")
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
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error = error {
                Logger.error("Error fetching FCM registration token: \(error)")
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

    func application(_: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        if let notiflyMessageType = userInfo["notifly_message_type"] as? String,
           let notiflyInAppMessageData = userInfo["notifly_in_app_message_data"] as? String,
           let data = Data(base64Encoded: notiflyInAppMessageData),
           let decodedInAppMessageData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           notiflyMessageType == "in-app-message"
        {
            if WebViewModalViewController.openedInAppMessageCount == 0,
               UIApplication.shared.applicationState == .active,
               let urlString = decodedInAppMessageData["url"] as? String,
               let notiflyInAppMessageData = [
                   "urlString": urlString,
                   "notiflyMessageID": decodedInAppMessageData["notifly_message_id"],
                   "notiflyCampaignID": decodedInAppMessageData["campaign_id"],
                   "modalProps": decodedInAppMessageData["modal_properties"],
               ] as? [String: Any]
            {
                showInAppMessage(notiflyInAppMessageData: notiflyInAppMessageData, completion: completionHandler)
            }

        } else {
            completionHandler(.noData)
        }
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

    private func showInAppMessage(notiflyInAppMessageData: [String: Any], completion: (UIBackgroundFetchResult) -> Void) {
        guard let urlString = notiflyInAppMessageData["urlString"] as? String,
              let url = URL(string: urlString),
              let modalProps = notiflyInAppMessageData["modalProps"] as? [String: Any]
        else {
            completion(.noData)
            return
        }
        try? presentNotiflyInAppMessage(url: url, notiflyCampaignID: notiflyInAppMessageData["notiflyCampaignID"] as? String, notiflyMessageID: notiflyInAppMessageData["notiflyMessageID"] as? String, modalProps: modalProps)
        completion(.noData)
    }

    private func logPushClickInternalEvent(pushData: [AnyHashable: Any], clickStatus: String) {
        if let campaignID = pushData["campaign_id"] as? String {
            let messageID = pushData["notifly_message_id"] ?? "" as String
            if let pushClickEventParams = [
                "type": "message_event",
                "channel": "push-notification",
                "campaign_id": campaignID,
                "notifly_message_id": messageID,
                "click_status": clickStatus,
            ] as? [String: Any] {
                Notifly.main.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.pushClickEventName, eventParams: pushClickEventParams)
            }
        }
    }

    private func presentNotiflyInAppMessage(url: URL?, notiflyCampaignID: String?, notiflyMessageID: String?, modalProps: [String: Any]?) {
        do {
            let vc = try WebViewModalViewController(url: url, notiflyCampaignID: notiflyCampaignID, notiflyMessageID: notiflyMessageID, modalProps: modalProps)
            AppHelper.present(vc, completion: nil)
        } catch {
            Logger.error("Error presenting in-app message: \(error.localizedDescription)")
        }
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(_: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void)
    {
        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]?,
           let clickStatus = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        {
            if let urlString = pushData["url"] as? String,
               let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    self.logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
                }
            } else {
                logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
            }
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        completion()
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(_: UNUserNotificationCenter,
                                       willPresent _: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        completion([.banner, .badge, .sound])
    }
}
