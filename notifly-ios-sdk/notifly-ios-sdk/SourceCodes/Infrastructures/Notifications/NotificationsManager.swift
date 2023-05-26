import Combine
import FirebaseMessaging
import Foundation
import SafariServices
import UIKit
import UserNotifications

class NotificationsManager: NSObject {
    // MARK: Properties

    private var _deviceTokenPub: AnyPublisher<String, Error>?

    private(set) var deviceTokenPub: AnyPublisher<String, Error>? {
        // TODO: Remove this temp workaround once APNs token is available.
        get {
            if let pub = _deviceTokenPub {
                return pub
                    .catch { _ in
                        Logger.error("Failed to get APNs Token with error: You don't register APNs token to notifly yet.")
                        return Just("").setFailureType(to: Error.self)
                    }
                    .eraseToAnyPublisher()
            } else {
                Logger.error("Failed to get APNs Token with error")
                return Just("").setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }
        set {
            _deviceTokenPub = newValue
        }
    }

    var deviceTokenPromise: Future<String, Error>.Promise?
    private var deviceTokenPromiseTimeoutInterval: TimeInterval = 5.0

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
            if let token = token, error == nil {
                self.deviceTokenPromise?(.success(token))
                self.deviceTokenPub = Just(token).setFailureType(to: Error.self).eraseToAnyPublisher()
            } else {
                Logger.error("Error fetching FCM registration token: \(error)")
                self.deviceTokenPromise?(.failure(NotiflyError.deviceTokenError))
                self.deviceTokenPub = Fail(error: NotiflyError.deviceTokenError).eraseToAnyPublisher()
            }
        }
    }

    func application(_: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        Logger.error("Failed to receive the push notification deviceToken with error: \(error)")
        deviceTokenPromise?(.failure(error))
    }

    func handleDataMessage(didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        guard (try? Notifly.main) != nil else {
            Logger.error("Fail to receive Notifly In App Message: Notifly is not initialized yet.")
            return
        }
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
                showInAppMessage(notiflyInAppMessageData: notiflyInAppMessageData)
            }
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
        deviceTokenPub = Future { [weak self] promise in
            self?.deviceTokenPromise = promise
            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.deviceTokenPromiseTimeoutInterval ?? 0.0)) {
                if let promise = self?.deviceTokenPromise {
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }.eraseToAnyPublisher()

        // Register Remote Notification.
        if !(UIApplication.shared.isRegisteredForRemoteNotifications && Globals.isRegisteredAPNsInUserDefaults == true) {
            UIApplication.shared.registerForRemoteNotifications()
            Globals.isRegisteredAPNsInUserDefaults = true
        }

        if let pushData = Notifly.coldStartNotificationData {
            let clickStatus = "background"
            if let urlString = pushData["url"] as? String,
               let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    self.logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
                }
            } else {
                logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
            }
            Notifly.coldStartNotificationData = nil
        }
    }

    private func showInAppMessage(notiflyInAppMessageData: [String: Any]) {
        guard let urlString = notiflyInAppMessageData["urlString"] as? String,
              let url = URL(string: urlString),
              let modalProps = notiflyInAppMessageData["modalProps"] as? [String: Any]
        else {
            return
        }

        do {
            let vc = try WebViewModalViewController(url: url, notiflyCampaignID: notiflyInAppMessageData["notiflyCampaignID"] as? String, notiflyMessageID: notiflyInAppMessageData["notiflyMessageID"] as? String, modalProps: modalProps)
            AppHelper.present(vc, completion: nil)
        } catch {
            Logger.error("Error presenting in-app message")
        }
    }

    private func logPushClickInternalEvent(pushData: [AnyHashable: Any], clickStatus: String) {
        guard let notifly = try? Notifly.main else {
            return
        }
        if let campaignID = pushData["campaign_id"] as? String {
            let messageID = pushData["notifly_message_id"] ?? "" as String
            if let pushClickEventParams = [
                "type": "message_event",
                "channel": "push-notification",
                "campaign_id": campaignID,
                "notifly_message_id": messageID,
                "click_status": clickStatus,
            ] as? [String: Any] {
                notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.pushClickEventName, eventParams: pushClickEventParams)
            }
        }
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(_: UNUserNotificationCenter,
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
            guard (try? Notifly.main) != nil else {
                Notifly.coldStartNotificationData = pushData
                return
            }
            if let urlString = pushData["url"] as? String,
               let url = URL(string: urlString)
            {
                UIApplication.shared.open(url, options: [:]) { _ in
                    self.logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
                }
            } else {
                logPushClickInternalEvent(pushData: pushData, clickStatus: clickStatus)
            }
        }
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(_: UNUserNotificationCenter,
                                       willPresent _: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void)
    {
        if #available(iOS 14.0, *) {
            completion([.banner, .badge, .sound])
        } else {
            completion([.alert, .badge, .sound])
        }
    }
}
