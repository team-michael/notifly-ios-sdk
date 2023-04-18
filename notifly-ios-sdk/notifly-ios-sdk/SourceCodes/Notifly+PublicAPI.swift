import Foundation
import Combine
import UIKit

/**
 Contains all available Notifly SDK Public APIs.
 */
public extension Notifly {
    
    /**
     Initializes the Notifly SDK. This method is to be called as soon as the app laucnhes. (AppDelegate.applicationDidFinishLaunching)
     */
    static func initialize(projectID: String,
                           username: String,
                           password: String,
                           useCustomClickHandler: Bool) {
        main = Notifly(projectID: projectID,
                       username: username,
                       password: password,
                       useCustomClickHandler: useCustomClickHandler)
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
    
    static func track(eventName: String,
                      eventParams: [String: String]?,
                      segmentationEventParamKeys: [String]?,
                      userID: String?) -> AnyPublisher<String, Error> {
        return main.trackingManager.track(eventName: eventName,
                                          eventParams: eventParams,
                                          segmentationEventParamKeys: segmentationEventParamKeys,
                                          userID: userID)
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
