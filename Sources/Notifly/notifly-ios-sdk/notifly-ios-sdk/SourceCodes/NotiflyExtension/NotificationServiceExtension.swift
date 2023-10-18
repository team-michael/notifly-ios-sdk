//
//  NotificationServiceExtension.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/09/13.
//

import Combine
import UserNotifications

@objc open class NotiflyNotificationServiceExtension: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    open func register(projectId: String, username: String) {
        NotiflyCustomUserDefaults.register(projectId: projectId, org: username)
    }
    
    override open func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return
        }
        self.bestAttemptContent = bestAttemptContent
        self.contentHandler = contentHandler

        guard let notiflyMessageType = bestAttemptContent.userInfo["notifly_message_type"] as? String,
              notiflyMessageType == "push-notification"
        else {
            contentHandler(bestAttemptContent)
            return
        }
        
        if let projectId = NotiflyCustomUserDefaults.projectIdInUserDefaults,
           NotiflyCustomUserDefaults.usernameInUserDefaults != nil,
           NotiflyCustomUserDefaults.passwordInUserDefaults != nil
        {
            let data = [
                "type": "message_event",
                "channel": "push-notification",
                "campaign_id": bestAttemptContent.userInfo["campaign_id"] ?? "",
                "notifly_message_id": bestAttemptContent.userInfo["notifly_message_id"] ?? "",
            ] as [String: Any]
            ExtensionManager(projectId: projectId)
                .track(eventName: TrackingConstant.Internal.pushNotificationMessageShown, params: data)
        } else {
            Logger.error("Cannot Access to NotiflyCustomUserDefaults. Please confirm that the app group identifier is 'group.notifly.{username}.'")
        }
        
        ExtensionManager.show(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
    }

    override open func serviceExtensionTimeWillExpire() {
        Logger.info("Service Extension Expired")
        if let contentHandler = contentHandler as? ((UNNotificationContent) -> Void), let bestAttemptContent = bestAttemptContent as? UNMutableNotificationContent {
            contentHandler(bestAttemptContent)
        }
    }
}

@objc public class ExtensionManager: NSObject {
    private let projectId: String
    init(
        projectId: String
    ) {
        self.projectId = projectId
    }

    static func show(bestAttemptContent: UNMutableNotificationContent, contentHandler: @escaping ((UNNotificationContent) -> Void)) {
        guard let rawAttachmentData = (bestAttemptContent.userInfo["notifly_attachment"] as? String)?.data(using: .utf8),
              let attachmentData = (try? JSONSerialization.jsonObject(with: rawAttachmentData, options: [])) as? [String: Any],
              let attachment = try? PushAttachment(attachment: attachmentData)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        let task = URLSession.shared.downloadTask(with: attachment.url) { downloadedUrl, _, error in
            if let _ = error {
                contentHandler(bestAttemptContent)
                return
            }

            if let downloadedUrl = downloadedUrl, let attachment = try? UNNotificationAttachment(identifier: "notifly_push_notification_attachment", url: downloadedUrl, options: [UNNotificationAttachmentOptionsTypeHintKey: attachment.attachmentFileType]) {
                bestAttemptContent.attachments = [attachment]
            }
            contentHandler(bestAttemptContent)
        }
        task.resume()
    }

    func track(eventName: String, params: [String: Any]?) {
        guard let payload = preparePayload(eventName: eventName, params: params) else {
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

    private func preparePayload(eventName: String, params: [String: Any]?) -> TrackingRecord? {
        let userID = getUserId()
        if let notiflyDeviceID = AppHelper.getNotiflyDeviceID(),
           let deviceID = AppHelper.getDeviceID(),
           let appVersion = AppHelper.getAppVersion(),
           let data = TrackingData(id: UUID().uuidString,
                                   name: TrackingConstant.Internal.pushNotificationMessageShown,
                                   notifly_user_id: userID,
                                   external_user_id: NotiflyCustomUserDefaults.externalUserIdInUserDefaults,
                                   time: Int(Date().timeIntervalSince1970),
                                   notifly_device_id: notiflyDeviceID,
                                   external_device_id: deviceID,
                                   device_token: "",
                                   is_internal_event: true,
                                   segmentation_event_param_keys: [],
                                   project_id: projectId,
                                   platform: AppHelper.getDevicePlatform(),
                                   os_version: AppHelper.getiOSVersion(),
                                   app_version: appVersion,
                                   sdk_version: "",
                                   sdk_type: "",
                                   event_params: AppHelper.makeJsonCodable(params)) as? TrackingData,
           let stringfiedData = try? String(data: JSONEncoder().encode(data), encoding: .utf8)
        {
            return TrackingRecord(partitionKey: userID, data: stringfiedData)
        } else {
            Logger.error("Failed to track event: " + eventName)
            return nil
        }
    }

    private func getUserId() -> String {
        let externalUserId = NotiflyCustomUserDefaults.externalUserIdInUserDefaults

        let uuidV5Namespace: UUID
        let uuidV5Name: String

        if externalUserId != nil {
            uuidV5Name = "\(projectId)\(externalUserId)"
            uuidV5Namespace = TrackingConstant.HashNamespace.registeredUserID
        } else {
            let deviceID = AppHelper.getDeviceID()
            uuidV5Name = "\(projectId)\(deviceID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }

        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }
}
