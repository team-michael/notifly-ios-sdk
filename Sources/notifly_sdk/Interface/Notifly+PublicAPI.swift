import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// Configures the Notifly SDK and wrapper metadata.
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {

    /// Initializes Notifly for the host application and starts its background services.
    ///
    /// Call this method from the main thread during application launch, after configuring
    /// Firebase. A missing default Firebase app or an invalid project ID is logged and
    /// does not create a new SDK instance. Successful setup queues user-state synchronization,
    /// session tracking, and the server-sent event connection; returning does not mean
    /// these asynchronous operations have completed.
    ///
    /// Initialize once per application launch. Calling again replaces the SDK instance
    /// and invalidates the previous instance's server-sent event connection.
    ///
    /// - Parameters:
    ///   - projectId: The Notifly project identifier associated with the application.
    ///   - username: The SDK authentication username. It also selects the shared
    ///     preferences suite named `group.notifly.<username>` for the app and extension.
    ///   - password: The SDK authentication password for the supplied username.
    /// - Important: The host app and notification service extension must use matching
    ///   project and App Group settings to share notification-related SDK state.
    ///
    /// ```swift
    /// Notifly.initialize(
    ///     projectId: "YOUR_PROJECT_ID",
    ///     username: "YOUR_USERNAME",
    ///     password: "YOUR_PASSWORD"
    /// )
    /// ```
    static func initialize(
        projectId: String,
        username: String,
        password: String
    ) {
        guard FirebaseApp.app() != nil else {
            Logger.error(
                "FirebaseApp is not initialized. Please initialize FirebaseApp before calling Notifly.initialize."
            )
            return
        }

        if !NotiflyHelper.testRegex(projectId, regex: NotiflyConstant.projectIdRegex) {
            Logger.error("Invalid Project ID. Please provide a valid Project ID.")
            return
        }

        Notifly.setup(
            projectId: projectId,
            username: username,
            password: password
        )

        guard let main = try? Notifly.main else {
            Logger.error("Failed to initialize Notifly.")
            return
        }

        Notifly.asyncWorker.addTask { finishTask in
            main.inAppMessageManager.userStateManager.syncState(
                postProcessConfig:
                    PostProcessConfigForSyncState(merge: false, clear: false),
                handleExternalUserIdMismatch: true
            ) {
                finishTask()
            }
        }

        if let pushData = Notifly.coldStartNotificationData {
            if Notifly.coldStartNotificationActionIdentifier
                == NotiflyConstant.AdPush.unsubscribeActionIdentifier
            {
                // On a cold-start unsubscribe action, open unsubscribe_url instead of the message URL.
                if let urlString = pushData[NotiflyConstant.AdPush.unsubscribeUrlKey] as? String,
                    let url = URL(string: urlString)
                {
                    UIApplication.shared.open(url, options: [:])
                }
            }
            else {
                let clickStatus = "background"
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
            Notifly.coldStartNotificationData = nil
            Notifly.coldStartNotificationActionIdentifier = nil
        }

        // NotificationsManager now handles all token acquisition logic
        Notifly.asyncWorker.addTask { finishTask in
            main.trackingManager.trackSessionStartInternalEvent()
            Logger.info("📡 Notifly SDK is successfully initialized.")
            finishTask()
        }

        Notifly.asyncWorker.addTask { finishTask in
            main.registerSSELifecycleObservers()
            main.startSSE()
            finishTask()
        }
    }

    /// Sets the wrapper SDK type attached to subsequent SDK metadata.
    ///
    /// This integration hook is intended for wrapper SDKs. It can be called before
    /// initialization and updates in-memory configuration synchronously. An unsupported
    /// value is logged and leaves the existing configuration unchanged.
    ///
    /// - Parameter type: A `SdkWrapperType` raw value: `react_native` or `flutter`.
    static func setSdkType(type: String) {
        if let sdkType = SdkWrapperType(rawValue: type) {
            NotiflySdkConfig.sdkWrapperType = sdkType
            Logger.info("Notifly SDK type has been set to \(sdkType.rawValue).")
        }
        else {
            Logger.error(
                "Notifly SDK type is invalid. Please set type to one of the following: 'react_native', 'flutter'"
            )
        }
    }

    /// Sets the wrapper SDK version attached to subsequent SDK metadata.
    ///
    /// Wrapper SDKs can call this before initialization alongside `setSdkType(type:)`.
    /// The value is stored in memory synchronously and is not validated or persisted.
    ///
    /// - Parameter version: The wrapper library's version string, such as `4.6.0`.
    static func setSdkVersion(version: String) {
        NotiflySdkConfig.sdkWrapperVersion = version
    }
}
