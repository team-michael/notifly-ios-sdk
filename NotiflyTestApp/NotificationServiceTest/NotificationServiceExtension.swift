import UserNotifications
import MobileCoreServices

@objc public class NotificationServiceExtensionHelper: NSObject {
  @objc public static let shared = NotificationServiceExtensionHelper()
  
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?
  
  @objc public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    
    
    self.contentHandler = contentHandler
    bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
    
    if let bestAttemptContent = bestAttemptContent {
      guard let imageData = request.content.userInfo["fcm_options"] as? [String : Any],
            let imageUrl = imageData["image"] as? String,
                let attachmentUrl = URL(string: imageUrl) else {
          contentHandler(bestAttemptContent)
          return
      }
      
      let task = URLSession.shared.downloadTask(with: attachmentUrl) { (downloadedUrl, response, error) in
        if let _ = error {
          contentHandler(bestAttemptContent)
          return
        }
        
        if let downloadedUrl = downloadedUrl, let attachment = try? UNNotificationAttachment(identifier: "notification_attachment", url: downloadedUrl, options: [UNNotificationAttachmentOptionsTypeHintKey: kUTTypePNG]) {
          bestAttemptContent.attachments = [attachment]
        }
        
        contentHandler(bestAttemptContent)
      }
      
      task.resume()
    }
  }
  
  @objc public func serviceExtensionTimeWillExpire() {
      print("EXPIRE")
      if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
          contentHandler(bestAttemptContent)
      }
  }

}
