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

    private var _deviceTokenPub: AnyPublisher<String, Error>?

    // Token state tracking
    private var apnsTokenState: TokenState = .pending
    private var fcmTokenState: TokenState = .pending
    private var currentDeviceToken: Data?
    private var lastFCMToken: String?

    // Retry configuration
    private let maxRetryAttempts: Int = 4
    private var apnsRetryAttempt: Int = 0
    private var fcmRetryAttempt: Int = 0

    // Timeout configuration
    private var deviceTokenPromiseTimeoutInterval: TimeInterval = 10.0  // Increased from 5.0
    private let retryBaseDelay: TimeInterval = 1.0

    // Timer management
    private var timeoutWorkItem: DispatchWorkItem?

    private(set) var deviceTokenPub: AnyPublisher<String, Error>? {
        get {
            guard let pub = _deviceTokenPub else {
                Logger.error("Failed to get APNs Token - no publisher available")

                // Check if we can start token acquisition
                if apnsTokenState == .pending || apnsTokenState == .failed {
                    startTokenAcquisition()
                }

                return Fail(error: NotiflyError.deviceTokenError)
                    .eraseToAnyPublisher()
            }
            return
                pub
                .catch { [weak self] error -> AnyPublisher<String, Error> in
                    Logger.error("Failed to get APNs Token with error: \(error)")

                    // Instead of returning empty string, attempt retry
                    guard let self = self, case .failed = self.apnsTokenState else {
                        // If retry is not possible, fail properly instead of empty string
                        return Fail(error: NotiflyError.deviceTokenError)
                            .eraseToAnyPublisher()
                    }
                    return self.createRetryPublisher()
                }
                .eraseToAnyPublisher()
        }
        set {
            _deviceTokenPub = newValue
        }
    }

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
        currentDeviceToken = deviceToken
        apnsTokenState = .success
        // Don't reset retry counter here - let it be reset only when FCM token succeeds

        // Convert APNs token to string for tracking
        let apnsTokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        // Track APNs token for debugging purposes
        if let notifly = try? Notifly.main {
            notifly.trackingManager.trackSetDevicePropertiesInternalEvent(properties: [
                "apns_token": apnsTokenString
            ])
        }

        // Set APNs token to Firebase
        Messaging.messaging().apnsToken = deviceToken

        // Request FCM token with retry logic
        requestFCMTokenWithRetry()
    }

    func registerFCMToken(token: String) {
        // 중복/재진입 가드: 동일 토큰으로 이미 성공 처리된 경우 조기 종료
        if token == lastFCMToken, fcmTokenState == .success {
            if let promise = deviceTokenPromise {
                // 비정상적으로 promise가 남아있다면 한 번만 완료 후 정리
                promise(.success(token))
                deviceTokenPromise = nil
            }
            return
        }

        Logger.info("🔥 FCM token registered successfully")
        fcmTokenState = .success
        fcmRetryAttempt = 0  // Reset retry counter on success
        apnsRetryAttempt = 0  // Reset APNs retry counter on FCM success

        // Cancel the timeout timer since we successfully got the token
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let shouldTrackDeviceTokenEvent = (lastFCMToken != token)
        lastFCMToken = token

        // deviceTokenPromise 단일 완료 보장 및 즉시 nil 처리
        if let promise = deviceTokenPromise {
            promise(.success(token))
            deviceTokenPromise = nil
        }

        deviceTokenPub = Just(token).setFailureType(to: Error.self).eraseToAnyPublisher()

        // 세션 내 동일 토큰 기반 중복 내부 이벤트 전송/중복 등록 방지
        if shouldTrackDeviceTokenEvent, let notifly = try? Notifly.main {
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
        apnsTokenState = .failed

        // Cancel the timeout timer since we got a definitive result
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        // Start APNs retry logic
        retryAPNsRegistration()
    }

    // MARK: - Token Acquisition & Retry Logic

    private func startTokenAcquisition() {
        Logger.info("🚀 Starting token acquisition process")
        apnsTokenState = .pending
        fcmTokenState = .pending

        setupDeviceTokenPublisher()
        registerForRemoteNotifications()
    }

    private func setupDeviceTokenPublisher() {
        // Cancel any existing timeout timer
        timeoutWorkItem?.cancel()

        // Setup observer to listen for APN Device tokens with extended timeout
        deviceTokenPub = Future { [weak self] promise in
            self?.deviceTokenPromise = promise

            // Create new timeout work item
            let workItem = DispatchWorkItem { [weak self] in
                if let self = self, let promise = self.deviceTokenPromise {
                    Logger.error("⏰ Device token promise timeout reached")
                    self.apnsTokenState = .failed
                    promise(.failure(NotiflyError.promiseTimeout))

                    // Clear the work item since it's executed
                    self.timeoutWorkItem = nil

                    // Start retry process
                    self.retryAPNsRegistration()
                }
            }

            // Store and schedule the work item
            self?.timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (self?.deviceTokenPromiseTimeoutInterval ?? 10.0),
                execute: workItem
            )
        }.eraseToAnyPublisher()
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
        guard apnsRetryAttempt < maxRetryAttempts else {
            Logger.error("❌ APNs registration failed after \(maxRetryAttempts) attempts")
            apnsTokenState = .failed
            // 안정성 가드: promise를 한 번만 실패로 종료하고 즉시 정리
            if let promise = deviceTokenPromise {
                promise(.failure(NotiflyError.deviceTokenError))
                deviceTokenPromise = nil
            }
            // 지연 타임아웃이 남아있다면 해제하여 중복 완료/충돌 방지
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            return
        }

        apnsRetryAttempt += 1
        apnsTokenState = .retrying(attempt: apnsRetryAttempt)

        let delay = retryBaseDelay * pow(2.0, Double(apnsRetryAttempt - 1))  // Exponential backoff
        Logger.info(
            "🔄 Retrying APNs registration (attempt \(apnsRetryAttempt)/\(maxRetryAttempts)) after \(delay)s"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.registerForRemoteNotifications()
            self?.setupDeviceTokenPublisher()
        }
    }

    // MARK: - FCM Retry Logic

    private func requestFCMTokenWithRetry() {
        fcmTokenState = .pending

        Messaging.messaging().token { [weak self] token, error in
            guard let self = self else { return }

            if let token = token, error == nil {
                self.registerFCMToken(token: token)
            } else {
                Logger.error(
                    "Error fetching FCM registration token: \(error?.localizedDescription ?? "Unknown error")"
                )
                self.fcmTokenState = .failed
                self.retryFCMTokenRequest()
            }
        }
    }

    private func retryFCMTokenRequest() {
        guard fcmRetryAttempt < maxRetryAttempts else {
            Logger.error("❌ FCM token request failed after \(maxRetryAttempts) attempts")
            fcmTokenState = .failed
            return
        }

        // Ensure APNs token is available before retrying FCM
        guard let deviceToken = currentDeviceToken, apnsTokenState == .success else {
            Logger.error("⚠️ Cannot retry FCM token request: APNs token not available")

            // If APNs token is not available, wait and retry
            let delay = retryBaseDelay * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.retryFCMTokenRequest()
            }
            return
        }

        fcmRetryAttempt += 1
        fcmTokenState = .retrying(attempt: fcmRetryAttempt)

        let delay = retryBaseDelay * pow(2.0, Double(fcmRetryAttempt - 1))  // Exponential backoff
        Logger.info(
            "🔄 Retrying FCM token request (attempt \(fcmRetryAttempt)/\(maxRetryAttempts)) after \(delay)s"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            // Ensure APNs token is still set
            Messaging.messaging().apnsToken = deviceToken

            // Request FCM token again
            self.requestFCMTokenWithRetry()
        }
    }

    // MARK: - Fallback Publisher for Retry

    private func createRetryPublisher() -> AnyPublisher<String, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotiflyError.deviceTokenError))
                return
            }

            Logger.info("🔄 Creating retry publisher for token acquisition")

            // Store the promise for later resolution
            self.deviceTokenPromise = promise

            // Start the retry process
            if self.apnsTokenState == .failed {
                self.apnsRetryAttempt = 0  // Reset for new attempt
                self.retryAPNsRegistration()
            }
        }.eraseToAnyPublisher()
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

#if DEBUG
// MARK: - Test Hooks (DEBUG only)
extension NotificationsManager {
    /// FCM 최대 재시도 초과 상황을 강제하여 현재 사이클 상태를 검사하기 위한 테스트 훅
    func test_simulateFCMMaxRetryExceeded() {
        fcmRetryAttempt = maxRetryAttempts
        retryFCMTokenRequest()
    }

    /// APNs 최대 재시도 초과 상황을 강제하여 정리 로직을 검사하기 위한 테스트 훅
    func test_simulateAPNsMaxRetryExceeded() {
        apnsRetryAttempt = maxRetryAttempts
        retryAPNsRegistration()
    }

    /// 테스트에서 내부 상태/리소스 정리 여부를 확인하기 위한 헬퍼들
    func test_isDeviceTokenPromiseNil() -> Bool { deviceTokenPromise == nil }
    func test_isTimeoutWorkItemNil() -> Bool { timeoutWorkItem == nil }
    func test_getLastFCMToken() -> String? { lastFCMToken }
    func test_getFCMState() -> TokenState { fcmTokenState }
    func test_getAPNsState() -> TokenState { apnsTokenState }
}
#endif
