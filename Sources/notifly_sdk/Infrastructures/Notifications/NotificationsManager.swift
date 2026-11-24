import Combine
import FirebaseMessaging
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class NotificationsManager: NSObject {

    // Token state and promise mutations are protected by stateQueue.
    private let stateQueue = DispatchQueue(label: "com.notifly.notificationsManager.state")

    private var _deviceTokenPub: AnyPublisher<String, Error>?

    private var apnsTokenState: TokenState = .pending
    private var fcmTokenState: TokenState = .pending
    private var currentDeviceToken: Data?
    private var lastFCMToken: String?
    private var lastAPNsToken: String?
    private var isFCMRequestInFlight: Bool = false

    private let maxRetryAttempts: Int = 4
    private var apnsRetryAttempt: Int = 0
    private var fcmRetryAttempt: Int = 0

    private var deviceTokenPromiseTimeoutInterval: TimeInterval = 10.0
    private let retryBaseDelay: TimeInterval = 1.0

    private var timeoutWorkItem: DispatchWorkItem?
    private var timeoutToken: UUID?

    private(set) var deviceTokenPub: AnyPublisher<String, Error>? {
        get {
            var publisher: AnyPublisher<String, Error>?
            var needsRestart = false

            stateQueue.sync {
                publisher = _deviceTokenPub
                if publisher == nil, apnsTokenState == .pending || apnsTokenState == .failed {
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
                    stateQueue.sync {
                        if case .failed = self.apnsTokenState {
                            // Recover immediately by resetting state and returning a publisher backed by a new Future.
                            Logger.info("🚀 Restarting token acquisition process")
                            self.apnsTokenState = .pending
                            self.fcmTokenState = .pending
                            self.setupDeviceTokenPublisher()
                            recovered = self._deviceTokenPub
                            restart = true
                        }
                        else {
                            recovered = self._deviceTokenPub
                        }
                    }

                    if restart {
                        registerForRemoteNotifications()
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

    var latestFCMToken: String? {
        stateQueue.sync { lastFCMToken }
    }

    var deviceTokenPromise: Future<String, Error>.Promise?

    override init() {
        super.init()
        setup()
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Logger.info("📱 APNs device token received")

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

        // Avoid duplicate APNs token events and the associated JSON encoding work.
        if shouldTrackAPNs, let notifly = try? Notifly.main {
            notifly.trackingManager.trackSetDevicePropertiesInternalEvent(properties: [
                "apns_token": apnsTokenString
            ])
        }

        // Assign APNs and request FCM in the same main-queue block so Firebase
        // associates the APNs token before Messaging.token(completion:) runs.
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
            // Avoid reentrant or duplicate registration of an already successful token.
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

        // Avoid duplicate device-token events and the associated JSON encoding work.
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

        let publisher = Future<String, Error> { [weak self] promise in
            guard let self = self else { return }

            stateQueue.async { [manager = self] in
                Logger.info("🔄 Creating device token publisher")
                manager.deviceTokenPromise = promise

                let token = UUID()
                manager.timeoutToken = token

                let workItem = DispatchWorkItem { [weak manager] in
                    guard let manager = manager else { return }

                    var promiseToFail: Future<String, Error>.Promise?
                    var shouldRetry = false

                    manager.stateQueue.sync {
                        guard manager.timeoutToken == token,
                            let promise = manager.deviceTokenPromise
                        else {
                            return
                        }
                        Logger.error("⏰ Device token promise timeout reached")
                        manager.apnsTokenState = .failed
                        promiseToFail = promise
                        manager.resetPromiseState()
                        shouldRetry = true
                    }

                    promiseToFail?(.failure(NotiflyError.promiseTimeout))

                    if shouldRetry {
                        manager.retryAPNsRegistration()
                    }
                }

                manager.timeoutWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + timeoutInterval,
                    execute: workItem
                )
            }
        }
        .eraseToAnyPublisher()

        _deviceTokenPub = publisher
    }

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

    private func requestFCMTokenWithRetry() {
        // Ignore reentrant requests while token acquisition is already in progress.
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

            stateQueue.async {
                self.isFCMRequestInFlight = false
            }

            if let token = token, error == nil {
                registerFCMToken(token: token)
            }
            else {
                Logger.error(
                    "Error fetching FCM registration token: \(error?.localizedDescription ?? "Unknown error")"
                )
                stateQueue.async {
                    self.fcmTokenState = .failed
                }
                retryFCMTokenRequest()
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

            requestFCMTokenWithRetry()
        }
    }

    // Clear the promise and its timeout together to keep their lifetimes consistent.
    private func resetPromiseState() {
        deviceTokenPromise = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        timeoutToken = nil
    }

    private func setup() {
        startTokenAcquisition()
        registerAdPushCategory()
    }
}
