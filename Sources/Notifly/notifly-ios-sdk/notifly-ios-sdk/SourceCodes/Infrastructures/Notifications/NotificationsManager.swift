import Combine
import FirebaseMessaging
import Foundation
import SafariServices
import UIKit
import UserNotifications

// MARK: - Token State Management
enum TokenState: Equatable {
    case pending
    case success
    case failed
    case retrying(attempt: Int)
}

@available(iOSApplicationExtension, unavailable)
class NotificationsManager: NSObject {
    // MARK: Properties

    // State queue (concurrency protection)
    private let stateQueue = DispatchQueue(label: "com.notifly.notificationsManager.state")

    // Device token publisher (stateQueue protected)
    private var _deviceTokenPub: AnyPublisher<String, Error>?

    // Token state tracking (stateQueue protected)
    private var apnsTokenState: TokenState = .pending
    private var fcmTokenState: TokenState = .pending
    private var currentDeviceToken: Data?
    private var lastFCMToken: String?
    private var lastAPNsToken: String?
    private var isFCMRequestInFlight: Bool = false

    // Retry configuration (stateQueue protected)
    private let maxRetryAttempts: Int = 4
    private var apnsRetryAttempt: Int = 0
    private var fcmRetryAttempt: Int = 0

    // Timeout configuration
    private var deviceTokenPromiseTimeoutInterval: TimeInterval = 10.0  // Increased from 5.0
    private let retryBaseDelay: TimeInterval = 1.0

    // Timer management (stateQueue protected)
    private var timeoutWorkItem: DispatchWorkItem?
    private var timeoutToken: UUID?

    private(set) var deviceTokenPub: AnyPublisher<String, Error>? {
        get {
            var publisher: AnyPublisher<String, Error>?
            var needsRestart = false

            stateQueue.sync {
                publisher = _deviceTokenPub
                if publisher == nil, (apnsTokenState == .pending || apnsTokenState == .failed) {
                    needsRestart = true
                }
            }

            if needsRestart {
                DispatchQueue.main.async { [weak self] in
                    self?.startTokenAcquisition()
                }
            }

            guard let basePublisher = publisher else {
                Logger.error("Failed to get APNs Token - no publisher available")
                return Fail(error: NotiflyError.deviceTokenError).eraseToAnyPublisher()
            }

            return basePublisher
                .catch { [weak self] error -> AnyPublisher<String, Error> in
                    Logger.error("Failed to get APNs Token with error: \(error)")

                    guard let self = self else {
                        return Fail(error: NotiflyError.deviceTokenError).eraseToAnyPublisher()
                    }

                    var recovered: AnyPublisher<String, Error>?
                    var restart = false
                    self.stateQueue.sync {
                        if case .failed = self.apnsTokenState {
                            // 즉시 회복: 상태 재설정 + 새 Future 준비 --> 퍼블리셔를 반환
                            Logger.info("🚀 Restarting token acquisition process")
                            self.apnsTokenState = .pending
                            self.fcmTokenState = .pending
                            self.setupDeviceTokenPublisher()
                            recovered = self._deviceTokenPub
                            restart = true
                        } else {
                            recovered = self._deviceTokenPub
                        }
                    }

                    if restart {
                        self.registerForRemoteNotifications()
                    }

                    return recovered ?? Fail(error: NotiflyError.deviceTokenError).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
        set {
            stateQueue.async { [weak self] in
                self?._deviceTokenPub = newValue
            }
        }
    }
    // Device token promise (stateQueue protected)
    var deviceTokenPromise: Future<String, Error>.Promise?

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
        Logger.info("📱 APNs device token received")

        // Convert APNs token to string for tracking
        let apnsTokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        var shouldTrackAPNs = false

        stateQueue.sync {
            currentDeviceToken = deviceToken
            apnsTokenState = .success
            if lastAPNsToken != apnsTokenString {
                lastAPNsToken = apnsTokenString
                shouldTrackAPNs = true
            }
        }

        // 동일 apns_token의 중복 내부 이벤트 전송 억제로 JSON 인코딩 스파이크 완화
        if shouldTrackAPNs, let notifly = try? Notifly.main {
            notifly.trackingManager.trackSetDevicePropertiesInternalEvent(properties: [
                "apns_token": apnsTokenString
            ])
        }

        // Assign the APNs token to Firebase and request the FCM token within the same
        // main-queue block so the assignment is guaranteed to happen before
        // Messaging.token(completion:) runs. Previously the assignment was dispatched
        // async while requestFCMTokenWithRetry() ran synchronously outside the block,
        // so the FCM token could be requested before the APNs token was associated —
        // yielding a stale/unassociated token on cold start and driving repeated token
        // re-acquisition. (This mirrors the ordering already used in the retry path.)
        DispatchQueue.main.async { [weak self] in
            Messaging.messaging().apnsToken = deviceToken
            self?.requestFCMTokenWithRetry()
        }
    }

    func registerFCMToken(token: String) {
        let publisher = Just(token).setFailureType(to: Error.self).eraseToAnyPublisher()

        var promiseToFulfill: Future<String, Error>.Promise?
        var shouldTrackDeviceTokenEvent = false

        stateQueue.sync {
            // 중복/재진입 가드 (동일 토큰으로 이미 성공 처리된 경우 조기 종료)
            if token == lastFCMToken, fcmTokenState == .success {
                promiseToFulfill = deviceTokenPromise
                resetPromiseState()
                return
            }

            Logger.info("🔥 FCM token registered successfully")
            fcmTokenState = .success
            fcmRetryAttempt = 0
            apnsRetryAttempt = 0

            shouldTrackDeviceTokenEvent = (lastFCMToken != token)
            lastFCMToken = token

            promiseToFulfill = deviceTokenPromise
            resetPromiseState()
            _deviceTokenPub = publisher
        }

        promiseToFulfill?(.success(token))

        // 동일 device_token의 중복 내부 이벤트 전송 억제로 JSON 인코딩 스파이크 완화
        if shouldTrackDeviceTokenEvent, let notifly = try? Notifly.main {
            notifly.trackingManager.trackSetDevicePropertiesInternalEvent(properties: [
                "device_token": token
            ])
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.error("Failed to receive the push notification deviceToken with error: \(error)")

        stateQueue.sync {
            apnsTokenState = .failed
            resetPromiseState()
        }

        retryAPNsRegistration()
    }

    // MARK: - Token Acquisition & Retry Logic

    private func startTokenAcquisition() {
        Logger.info("🚀 Starting token acquisition process")
        stateQueue.sync {
            if apnsTokenState == .failed {
                apnsRetryAttempt = 0
            }
            apnsTokenState = .pending
            fcmTokenState = .pending
            setupDeviceTokenPublisher()
        }
        registerForRemoteNotifications()
    }

    private func setupDeviceTokenPublisher() {
        resetPromiseState()

        let timeoutInterval = deviceTokenPromiseTimeoutInterval

        // Setup observer to listen for APN Device tokens with extended timeout
        let publisher = Future<String, Error> { [weak self] promise in
            guard let self = self else { return }

            self.stateQueue.async {
                Logger.info("🔄 Creating device token publisher")
                self.deviceTokenPromise = promise

                // Create new timeout work item
                let token = UUID()
                self.timeoutToken = token

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }

                    var promiseToFail: Future<String, Error>.Promise?
                    var shouldRetry = false

                    self.stateQueue.sync {
                        guard self.timeoutToken == token,
                            let promise = self.deviceTokenPromise else {
                            return
                        }
                        Logger.error("⏰ Device token promise timeout reached")
                        self.apnsTokenState = .failed
                        promiseToFail = promise
                        self.resetPromiseState()
                        shouldRetry = true
                    }

                    promiseToFail?(.failure(NotiflyError.promiseTimeout))

                    if shouldRetry {
                        self.retryAPNsRegistration()
                    }
                }

                // Store and schedule the work item
                self.timeoutWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + timeoutInterval,
                    execute: workItem
                )
            }
        }
        .eraseToAnyPublisher()

        _deviceTokenPub = publisher
    }

    private func registerForRemoteNotifications() {
        DispatchQueue.main.async { [weak self] in
            if !(UIApplication.shared.isRegisteredForRemoteNotifications
                && NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults == true)
            {
                Logger.info("📝 Registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
                NotiflyCustomUserDefaults.isRegisteredAPNsInUserDefaults = true
            } else {
                Logger.info("📝 Already registered for remote notifications, re-requesting...")
                // Force re-registration in case of retry
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - APNs Retry Logic

    private func retryAPNsRegistration() {
        var promiseToFail: Future<String, Error>.Promise?
        var attempt: Int = 0
        var delay: TimeInterval = 0

        let didReachLimit = stateQueue.sync { () -> Bool in
            if apnsRetryAttempt >= maxRetryAttempts {
                apnsTokenState = .failed
                promiseToFail = deviceTokenPromise
                _deviceTokenPub = Fail(error: NotiflyError.apnsTokenError).eraseToAnyPublisher()
                resetPromiseState()
                return true
            }

            apnsRetryAttempt += 1
            attempt = apnsRetryAttempt
            apnsTokenState = .retrying(attempt: apnsRetryAttempt)
            delay = retryBaseDelay * pow(2.0, Double(apnsRetryAttempt - 1))
            return false
        }

        if didReachLimit {
            Logger.error("❌ APNs registration failed after \(maxRetryAttempts) attempts")
            promiseToFail?(.failure(NotiflyError.apnsTokenError))
            return
        }

        Logger.info(
            "🔄 Retrying APNs registration (attempt \(attempt)/\(maxRetryAttempts)) after \(delay)s"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startTokenAcquisition()
        }
    }

    // MARK: - FCM Retry Logic

    private func requestFCMTokenWithRetry() {
        // 중복/재진입 가드 (이미 요청중이면 재진입 차단)
        let shouldRequest = stateQueue.sync { () -> Bool in
            if isFCMRequestInFlight {
                return false
            }
            isFCMRequestInFlight = true
            fcmTokenState = .pending
            return true
        }

        guard shouldRequest else { return }

        Messaging.messaging().token { [weak self] token, error in
            guard let self = self else { return }

            self.stateQueue.async {
                self.isFCMRequestInFlight = false
            }

            if let token = token, error == nil {
                self.registerFCMToken(token: token)
            } else {
                Logger.error(
                    "Error fetching FCM registration token: \(error?.localizedDescription ?? "Unknown error")"
                )
                self.stateQueue.async {
                    self.fcmTokenState = .failed
                }
                self.retryFCMTokenRequest()
            }
        }
    }

    private func retryFCMTokenRequest() {
        var promiseToFail: Future<String, Error>.Promise?
        var currentToken: Data?
        var attempt: Int = 0
        var delay: TimeInterval = 0
        var missingAPNsToken = false

        let reachedLimit = stateQueue.sync { () -> Bool in
            if fcmRetryAttempt >= maxRetryAttempts {
                fcmTokenState = .failed
                promiseToFail = deviceTokenPromise
                _deviceTokenPub = Fail(error: NotiflyError.fcmTokenError).eraseToAnyPublisher()
                resetPromiseState()
                return true
            }

            guard let deviceToken = currentDeviceToken, apnsTokenState == .success else {
                missingAPNsToken = true
                return false
            }

            fcmRetryAttempt += 1
            attempt = fcmRetryAttempt
            fcmTokenState = .retrying(attempt: fcmRetryAttempt)
            delay = retryBaseDelay * pow(2.0, Double(fcmRetryAttempt - 1))
            currentToken = deviceToken
            return false
        }

        if reachedLimit {
            Logger.error("❌ FCM token request failed after \(maxRetryAttempts) attempts")
            promiseToFail?(.failure(NotiflyError.fcmTokenError))
            return
        }

        // Ensure APNs token is available before retrying FCM
        if missingAPNsToken {
            Logger.error("⚠️ Cannot retry FCM token request: APNs token not available")
            let retryDelay = retryBaseDelay * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.retryFCMTokenRequest()
            }
            return
        }

        Logger.info(
            "🔄 Retrying FCM token request (attempt \(attempt)/\(maxRetryAttempts)) after \(delay)s"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            // Ensure APNs token is still set
            if let token = currentToken {
                Messaging.messaging().apnsToken = token
            }

            // Request FCM token again
            self.requestFCMTokenWithRetry()
        }
    }

    // promise/timer의 생명주기를 더 명확하게 관리하는 보조수단 (안정성 보강)
    private func resetPromiseState() {
        deviceTokenPromise = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        timeoutToken = nil
    }

    // MARK: - Original Methods (unchanged)

    func schedulePushNotification(
        title: String?,
        body: String?,
        url: URL,
        delay: TimeInterval
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            _,
            error in
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
                } else {
                    Logger.info("Notification scheduled successfully.")
                }
            }
        }
    }

    // MARK: Private Methods

    private func setup() {
        startTokenAcquisition()
    }
}

// MARK: - UNUserNotificationCenterDelegate

@available(iOSApplicationExtension, unavailable)
extension NotificationsManager: UNUserNotificationCenterDelegate {
    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(
        _: UNUserNotificationCenter,
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
        if #available(iOS 14.0, *) {
            completion([.banner, .badge, .sound, .list])
        } else {
            completion([.alert, .badge, .sound])
        }
    }
}
