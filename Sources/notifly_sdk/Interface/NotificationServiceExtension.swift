//
//  NotificationServiceExtension.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/09/13.
//

import Combine
import UserNotifications

/// Processes Notifly rich push notifications in a notification service extension.
///
/// Subclass this type in the extension target, register the same project and username
/// as the host app, and forward the notification-service lifecycle calls to `super`.
/// The SDK reads shared state, attempts delivery tracking, and downloads supported
/// attachments before passing the best available content to the system handler.
///
/// - Important: Configure the matching App Group entitlement in both targets so the
///   extension can read the credentials and identity stored by the host application.
@objc open class NotiflyNotificationServiceExtension: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    /// Selects the shared Keychain and preferences namespace used by this extension.
    ///
    /// Call before forwarding a notification to `didReceive(_:withContentHandler:)`.
    /// This selects the storage namespace; it does not authenticate or initialize the
    /// main application SDK. The host app is responsible for storing shared SDK state.
    ///
    /// - Parameters:
    ///   - projectId: The same Notifly project identifier used by the host application.
    ///   - username: The host app's SDK username, selecting `group.notifly.<username>`.
    open func register(projectId: String, username: String) {
        NotiflyStore.register(projectId: projectId, org: username, isExtension: true)
    }

    /// Processes an incoming notification and supplies the best available content.
    ///
    /// Non-Notifly payloads are returned unchanged when a mutable copy is available.
    /// For a Notifly push, delivery tracking is attempted independently of attachment
    /// processing. Missing or invalid attachment data returns the available content;
    /// a supported attachment is downloaded asynchronously before calling the handler.
    ///
    /// - Parameters:
    ///   - request: The notification request supplied to the service extension by iOS.
    ///   - contentHandler: The system completion closure receiving modified or original
    ///     content. It may run inline or from the download callback; no main-queue
    ///     dispatch is guaranteed.
    /// - Important: Forward `serviceExtensionTimeWillExpire()` as well so the SDK can
    ///   return its best available content when the extension's time budget expires.
    override open func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard
            let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
        else {
            return
        }
        self.bestAttemptContent = bestAttemptContent
        self.contentHandler = contentHandler

        guard
            let notiflyMessageType = bestAttemptContent.userInfo["notifly_message_type"] as? String,
            notiflyMessageType == "push-notification"
        else {
            contentHandler(bestAttemptContent)
            return
        }

        if let identity = try? NotiflyStore.loadIdentity(),
            identity.username != nil,
            NotiflyStore.password != nil
        {
            let gcmMessageId = bestAttemptContent.userInfo["gcm.message_id"] as? String
            let notiflyUserId = bestAttemptContent.userInfo["notifly_user_id"] as? String
            let data =
                [
                    "type": "message_event",
                    "channel": "push-notification",
                    "campaign_id": bestAttemptContent.userInfo["campaign_id"] ?? "",
                    "notifly_message_id": bestAttemptContent.userInfo["notifly_message_id"] ?? "",
                    "gcm_message_id": gcmMessageId ?? ""
                ] as [String: Any]
            ExtensionManager(projectId: identity.projectID)
                .track(
                    eventName: TrackingConstant.Internal.pushNotificationMessageShown,
                    params: data,
                    notiflyUserId: notiflyUserId
                )
        }
        else {
            Logger.error(
                "Cannot Access to NotiflyStore. Please confirm that the app group identifier is 'group.notifly.{username}.'"
            )
        }

        ExtensionManager.show(
            bestAttemptContent: bestAttemptContent,
            contentHandler: contentHandler
        )
    }

    /// Supplies retained notification content when the extension is about to expire.
    ///
    /// Forward the matching system lifecycle callback to this implementation. If both
    /// the content and completion handler from `didReceive` are available, the handler
    /// is invoked immediately with that content. Otherwise this method only logs expiry.
    /// It does not wait for or explicitly cancel an outstanding attachment download.
    override open func serviceExtensionTimeWillExpire() {
        Logger.info("Service Extension Expired")
        if let contentHandler = contentHandler,
            let bestAttemptContent = bestAttemptContent
        {
            contentHandler(bestAttemptContent)
        }
    }
}

/// Supports notification delivery tracking and attachment processing inside the SDK.
///
/// This type remains public for compatibility. Its processing entry points and
/// initializer are internal; applications integrate with
/// `NotiflyNotificationServiceExtension` rather than constructing this helper.
@objc public class ExtensionManager: NSObject {

    private let projectId: String

    init(
        projectId: String
    ) {
        self.projectId = projectId
    }

    static func show(
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping ((UNNotificationContent) -> Void)
    ) {
        guard
            let rawAttachmentData = (bestAttemptContent.userInfo["notifly_attachment"] as? String)?
                .data(using: .utf8),
            let attachmentData =
                (try? JSONSerialization.jsonObject(with: rawAttachmentData, options: []))
                as? [String: Any],
            let attachment = try? PushAttachment(attachment: attachmentData)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        let task = URLSession.shared.downloadTask(with: attachment.url) { downloadedUrl, _, error in
            if error != nil {
                contentHandler(bestAttemptContent)
                return
            }

            if let downloadedUrl = downloadedUrl,
                let attachment = try? UNNotificationAttachment(
                    identifier: "notifly_push_notification_attachment",
                    url: downloadedUrl,
                    options: [
                        UNNotificationAttachmentOptionsTypeHintKey: attachment.attachmentFileType
                    ]
                )
            {
                bestAttemptContent.attachments = [attachment]
            }
            contentHandler(bestAttemptContent)
        }
        task.resume()
    }

    func track(eventName: String, params: [String: Any]?, notiflyUserId: String?) {
        guard
            let payload = preparePayload(
                eventName: eventName,
                params: params,
                notiflyUserId: notiflyUserId
            )
        else {
            Logger.error("Fail to track push_delivered event.")
            return
        }

        NotiflyExtensionAPI().track(payload: payload) { res in
            switch res {
            case .success:
                return
            case let .failure(err):
                Logger.error("Fail to track push_delivered event.: \(err.localizedDescription)")
            }
        }
    }

    private func preparePayload(eventName: String, params: [String: Any]?, notiflyUserId: String?)
        -> TrackingRecord?
    {
        guard let identity = try? NotiflyStore.loadIdentity(),
            identity.projectID == projectId,
            let deviceID = identity.deviceID,
            let appVersion = AppHelper.getAppVersion()
        else {
            Logger.error("Failed to track event: " + eventName)
            return nil
        }

        let userID = notiflyUserId ?? getUserId(identity: identity)
        let notiflyDeviceID = UUID(
            name: deviceID,
            namespace: TrackingConstant.HashNamespace.deviceID
        ).notiflyStyleString

        let data = TrackingData(
            id: UUID().uuidString,
            name: TrackingConstant.Internal.pushNotificationMessageShown,
            notifly_user_id: userID,
            external_user_id: identity.externalUserID,
            time: AppHelper.getCurrentTimestamp(),
            notifly_device_id: notiflyDeviceID,
            external_device_id: deviceID,
            device_token: "",
            is_internal_event: true,
            segmentation_event_param_keys: [],
            project_id: projectId,
            platform: AppHelper.getDevicePlatform(),
            os_version: AppHelper.getiOSVersion(),
            app_version: appVersion,
            sdk_version: NotiflySdkConfig.sdkVersion,
            sdk_type: NotiflySdkConfig.sdkType,
            event_params: NotiflyAnyCodable(params)
        )

        guard let stringfiedData = try? String(data: JSONEncoder().encode(data), encoding: .utf8)
        else {
            Logger.error("Failed to track event: " + eventName)
            return nil
        }
        return TrackingRecord(partitionKey: notiflyDeviceID, data: stringfiedData)
    }

    private func getUserId(identity: StoredIdentity) -> String {
        let externalUserId = identity.externalUserID

        let uuidV5Namespace: UUID
        let uuidV5Name: String

        if externalUserId != nil {
            // Keep the legacy optional representation to preserve existing extension user IDs.
            uuidV5Name = "\(projectId)\(String(describing: externalUserId))"
            uuidV5Namespace = TrackingConstant.HashNamespace.registeredUserID
        }
        else {
            let deviceID = identity.deviceID
            uuidV5Name = "\(projectId)\(String(describing: deviceID))"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }

        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }
}
