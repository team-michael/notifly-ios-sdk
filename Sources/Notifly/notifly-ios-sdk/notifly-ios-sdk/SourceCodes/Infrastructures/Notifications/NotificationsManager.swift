import Combine
import FirebaseMessaging
import Foundation
import SafariServices
import UIKit
import UserNotifications


@objc public class NotiflyPushNotification: NSObject {
    @objc public let messageId: String
    @objc public let campaignId: String
    @objc public let title: String
    @objc public let body: String
    @objc public let url: String?
    @objc public let sentTime: NSNumber?
    @objc public let imageUrl: String?
    @objc public let payload: NSDictionary


    public init(messageId: String, campaignId: String, title: String, body: String, url: String?, sentTime: Int?, imageUrl: String?, payload: [String: Any]) {
        self.messageId = messageId
        self.campaignId = campaignId
        self.title = title
        self.body = body
        self.url = url
        self.sentTime = sentTime as NSNumber?
        self.imageUrl = imageUrl
        self.payload = payload as NSDictionary
    }
}

@available(iOSApplicationExtension, unavailable)
class NotificationsManager: NSObject {

    private var _deviceTokenPub: AnyPublisher<String, Error>?
    private var _clickListeners: [ (NotiflyPushNotification) -> Void] = [] // Now, it's only one listener.
    private let clickListenerAccessQueue = DispatchQueue(
label: "com.notifly.notificationsManager.clickListenerAccessQueue")
    var clickListeners: [ (NotiflyPushNotification) -> Void] {
        get {
            clickListenerAccessQueue.sync {
                _clickListeners
            }
        }
        set {
            clickListenerAccessQueue.sync {
                _clickListeners = newValue
            }
        }
    }
    

    private(set) var deviceTokenPub: AnyPublisher<String, Error>? {
        // TODO: Remove this temp workaround once APNs token is available.
        get {
            if let pub = _deviceTokenPub {
                return
                    pub
                    .catch { _ -> AnyPublisher<String, Error> in
                        Logger.error(
                            "Failed to get APNs Token with error: You don't register APNs token to notifly yet."
                        )
                        return Just("").setFailureType(to: Error.self).eraseToAnyPublisher()
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

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let token = token, error == nil {
                self.registerFCMToken(token: token)
            } else {
                Logger.error("Error fetching FCM registration token: \(error)")
                self.deviceTokenPromise?(.failure(NotiflyError.deviceTokenError))
                self.deviceTokenPub = Fail(error: NotiflyError.deviceTokenError)
                    .eraseToAnyPublisher()
            }
        }
    }

    func registerFCMToken(token: String) {
        deviceTokenPromise?(.success(token))
        deviceTokenPub = Just(token).setFailureType(to: Error.self).eraseToAnyPublisher()
        if let notifly = try? Notifly.main {
            notifly.trackingManager.trackSetDevicePropertiesInternalEvent(properties: [
                "device_token": token
            ])
        }
    }

    func setDeviceTokenPub(token: String) {
        deviceTokenPub = Just(token).setFailureType(to: Error.self).eraseToAnyPublisher()
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.error("Failed to receive the push notification deviceToken with error: \(error)")
        deviceTokenPromise?(.failure(error))
    }

    func schedulePushNotification(
        title: String?,
        body: String?,
        url: URL,
        delay: TimeInterval
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            _, error in
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
                identifier: UUID().uuidString, content: content, trigger: trigger)

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
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (self?.deviceTokenPromiseTimeoutInterval ?? 0.0)
            ) {
                if let promise = self?.deviceTokenPromise {
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }.eraseToAnyPublisher()

        // Register Remote Notification.
        DispatchQueue.main.async {
            if !(UIApplication.shared.isRegisteredForRemoteNotifications
                && NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults == true)
            {
                UIApplication.shared.registerForRemoteNotifications()
                NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults = true
            }
        }
    }

    func addNotificationClickListener(_ listener: @escaping (
        NotiflyPushNotification
    ) -> Void) {
        guard self.clickListeners.isEmpty else {
            Logger.error("Notification Click Listener is already registered.")
            return
        }

        self.clickListeners.append { notification in
            listener(notification)
        }

    }
}

@available(iOSApplicationExtension, unavailable)
extension NotificationsManager: UNUserNotificationCenterDelegate {
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) {
        if let pushData = response.notification.request.content.userInfo as? [String: Any?],
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

            // Tracking & Open URL
            if self.clickListeners.isEmpty,
               let urlString = pushData["url"] as? String,
               let url = URL(string: urlString) {
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

            // Custom Listener
            if !self.clickListeners.isEmpty {
                guard let title = response.notification.request.content.title as? String,
                      let body = response.notification.request.content.body as? String
                else {
                    return
                }
                
                self.clickListeners.forEach { listener in
                    var imageUrl: String? = nil
                    if let notiflyAttachment = pushData["notifly_attachment"] as? [String: Any?],
                       let url = notiflyAttachment["url"] as? String {
                        imageUrl = url
                    }
                    
                    listener(
                        NotiflyPushNotification(
                            messageId: title,
                            campaignId: body,
                            title: pushData["notifly_message_id"] as? String ?? "",
                            body: pushData["campaign_id"] as? String ?? "",
                            url: pushData["url"] as? String,
                            sentTime: pushData["sent_time"] as? Int,
                            imageUrl: imageUrl,
                            payload: (pushData as? [String : Any] ?? [:])
                        )
                    )
                }
            }
        }
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completion([.banner, .badge, .sound, .list])
        } else {
            completion([.alert, .badge, .sound])
        }
    }
}
