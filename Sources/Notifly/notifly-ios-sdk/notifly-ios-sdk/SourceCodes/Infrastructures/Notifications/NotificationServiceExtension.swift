//
//  NotificationServiceExtension.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/09/13.
//

import UserNotifications

open class NotiflyNotificationServiceExtension: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override open func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return
        }
        self.bestAttemptContent = bestAttemptContent
        self.contentHandler = contentHandler

        guard let notiflyMessageType = bestAttemptContent.userInfo["notifly_message_type"] as? String,
              notiflyMessageType == "push-notification" else {
            contentHandler(bestAttemptContent)
            return
        }
        showPushNotification()
        trackDeliveredEvent()
    }
    
    override open func serviceExtensionTimeWillExpire() {
        Logger.info("Service Extension Expired")
        if let contentHandler = contentHandler as? ((UNNotificationContent) -> Void), let bestAttemptContent =  bestAttemptContent as? UNMutableNotificationContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    func showPushNotification() {
        guard let bestAttemptContent = bestAttemptContent as? UNMutableNotificationContent,
        let contentHandler = contentHandler as? ((UNNotificationContent) -> Void) else {
            return
        }
        guard let rawAttachmentData = (bestAttemptContent.userInfo["notifly_attachment"] as? String)?.data(using: .utf8),
              let attachmentData = (try? JSONSerialization.jsonObject(with: rawAttachmentData, options: [])) as? [String:Any],
              let attachment = try? PushAttachment(attachment: attachmentData) else {
            contentHandler(bestAttemptContent)
            return
        }
        
        let task = URLSession.shared.downloadTask(with: attachment.url) { (downloadedUrl, response, error) in
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
    
    func trackDeliveredEvent() {
        guard let bestAttemptContent = bestAttemptContent as? UNMutableNotificationContent,
              let contentHandler = contentHandler as? ((UNNotificationContent) -> Void) else {
            return
        }
        
        let notifly: Notifly
        if let main = try? Notifly.main {
            notifly = main
        } else {
            guard let projectId = NotiflyCustomUserDefaults.projectIdInUserDefaults,
                  let username = NotiflyCustomUserDefaults.usernameInUserDefaults,
                  let password = NotiflyCustomUserDefaults.passwordInUserDefaults else {
                Logger.error("Fail to track push_delivered event.")
                return
            }
            notifly = Notifly(projectID: projectId, username: username, password: password, isMainApp: false)
        }
        
        let pushDeliveredEventParams = [
            "type": "message_event",
            "channel": "push-notification",
            "campaign_id": bestAttemptContent.userInfo["campaign_id"] ?? "",
            "notifly_message_id": bestAttemptContent.userInfo["notifly_message_id"] ?? ""
        ] as [String: Any]
        
        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.pushNotificationMessageShown, eventParams: pushDeliveredEventParams)
    }
}
