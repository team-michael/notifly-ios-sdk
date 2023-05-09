import FirebaseCore
import FirebaseMessaging
import Foundation
import Combine
import UIKit

/**
 Contains all available Notifly SDK Public APIs.
 */
public extension Notifly {
    
    // MARK: - Required Setup API configurations
    
    /**
     Initializes the Notifly SDK. This method is to be called as soon as the app laucnhes. (AppDelegate.applicationDidFinishLaunching)
     */
    static func initialize(projectID: String,
                           username: String,
                           password: String,
                           useCustomClickHandler: Bool) {
        FirebaseApp.configure() // TODO: Uncomment this once Firebase is configured properly for the project.
        
        main = Notifly(projectID: projectID,
                       username: username,
                       password: password,
                       useCustomClickHandler: useCustomClickHandler)
        
        Messaging.messaging().token { token, error in
            if let token = token,
               error == nil {
                main.notificationsManager.apnDeviceTokenPromise?(.success(token))
            }
        }
        
        if let externalUserID = Globals.externalUserIdInUserDefaults {
            main.userManager.externalUserID = externalUserID
        }

        Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.sessionStartEventName, params: nil)
    }
    
    static func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        main.notificationsManager.application(application,
                                              didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    static func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        main.notificationsManager.application(application,
                                              didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    // MARK: Optional Setup API configurations.
    // - Only use below APIs if your app implements custom push notification handler or passed `false` for `useCustomClickHandler` in the `initialize` method.
    
    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completion: () -> Void) {
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         didReceive: response,
                                                         withCompletionHandler: completion)
    }
    
    static func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void) {
        main.notificationsManager.userNotificationCenter(notificationCenter,
                                                         willPresent: notification,
                                                         withCompletionHandler: completion)
    }
    
    // MARK: - On-demand APIs
    
    static func trackEvent(name: String,
                           params: [String: String]?,
                           segmentationEventParamKeys: [String]?) {
        main.trackingManager.track(eventName: name,
                                   isInternal: false,
                                   params: params,
                                   segmentationEventParamKeys: segmentationEventParamKeys)
    }
    
    static func setUserID(_ userID: String?) throws {
        try main.userManager.setExternalUserID(userID)
    }
    
    static func setUserProperties(_ params: [String: String]) throws {
        try main.userManager.setUserProperties(params)
    }
    
    static func schedulePushNotification(title: String?,
                                         body: String?,
                                         url: URL,
                                         delay: TimeInterval) {
        main.notificationsManager.schedulePushNotification(title: title,
                                                           body: body,
                                                           url: url,
                                                           delay: delay)
    }
}
