import Combine
import FirebaseMessaging
import Foundation
import SafariServices
import UIKit
import UserNotifications

@available(iOSApplicationExtension, unavailable)
class NotificationsManager: NSObject {
    // MARK: Properties

    private var _deviceTokenPub: AnyPublisher<String, Error>?

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
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Logger.info("APNs device token received: \(tokenString)")

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            Logger.info(
                "Notification authorization status: authorized=\(settings.authorizationStatus == .authorized), alert=\(settings.alertSetting == .enabled), sound=\(settings.soundSetting == .enabled), badge=\(settings.badgeSetting == .enabled)"
            )
        }

        Messaging.messaging().apnsToken = deviceToken
        Logger.info("APNs token set to FCM: \(tokenString)")

        Messaging.messaging().token { token, error in
            if let token = token, error == nil {
                Logger.info("FCM registration token received: \(token)")
                Logger.info("FCM auto init enabled: \(Messaging.messaging().isAutoInitEnabled)")
                Logger.info(
                    "FCM APNs token matches: \(Messaging.messaging().apnsToken == deviceToken)")
                self.registerFCMToken(token: token)
            } else {
                Logger.error("Error fetching FCM registration token: \(error)")
                Logger.info("FCM error details: \(String(describing: error))")
                self.deviceTokenPromise?(.failure(NotiflyError.deviceTokenError))
                self.deviceTokenPub = Fail(error: NotiflyError.deviceTokenError)
                    .eraseToAnyPublisher()
            }
        }
    }

    func registerFCMToken(token: String) {
        Logger.info("Registering FCM token: \(token)")
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
                identifier: UUID().uuidString, content: content, trigger: trigger
            )

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
        Logger.info("Setting up NotificationsManager")

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            Logger.info(
                "Initial notification settings: authorized=\(settings.authorizationStatus == .authorized), alert=\(settings.alertSetting == .enabled), sound=\(settings.soundSetting == .enabled), badge=\(settings.badgeSetting == .enabled)"
            )
        }

        // Setup observer to listen for APN Device tokens.
        deviceTokenPub = Future { [weak self] promise in
            self?.deviceTokenPromise = promise
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (self?.deviceTokenPromiseTimeoutInterval ?? 0.0)
            ) {
                if let promise = self?.deviceTokenPromise {
                    Logger.info(
                        "Device token promise timed out after \(self?.deviceTokenPromiseTimeoutInterval ?? 0.0) seconds"
                    )
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }.eraseToAnyPublisher()

        // Register Remote Notification.
        DispatchQueue.main.async {
            let isRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
            let isRegisteredInDefaults =
                NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults == true

            Logger.info(
                "Remote notification registration status: isRegistered=\(isRegistered), isRegisteredInDefaults=\(isRegisteredInDefaults)"
            )

            if !(isRegistered && isRegisteredInDefaults) {
                Logger.info("Attempting to register for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
                NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults = true
                Logger.info("Remote notification registration initiated")
            } else {
                Logger.info("Remote notifications already registered")
            }
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
        Logger.info("Received notification response")
        Logger.info("Notification content: \(response.notification.request.content)")
        Logger.info("Notification userInfo: \(response.notification.request.content.userInfo)")
        Logger.info("App state: \(UIApplication.shared.applicationState)")

        if let pushData = response.notification.request.content.userInfo as [AnyHashable: Any]?,
            let clickStatus = UIApplication.shared.applicationState == .active
                ? "foreground" : "background"
        {
            Logger.info("Push data: \(pushData)")
            Logger.info("Click status: \(clickStatus)")
            Logger.info(
                "Push notification type: \(pushData["notifly_message_type"] as? String ?? "unknown")"
            )
            guard let notiflyMessageType = pushData["notifly_message_type"] as? String,
                notiflyMessageType == "push-notification"
            else {
                Logger.error("Invalid notifly_message_type in push data")
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
            } else {
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
        Logger.info("Will present notification in foreground")
        if #available(iOS 14.0, *) {
            completion([.banner, .badge, .sound, .list])
        } else {
            completion([.alert, .badge, .sound])
        }
    }
}
