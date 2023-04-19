
import Foundation
import Combine
import UIKit

class TrackingManager {
    
    private let projectID: String
    
    init(projectID: String) {
        self.projectID = projectID
    }
    
    func track(eventName: String,
               eventParams: [String: String]?,
               segmentationEventParamKeys: [String]?) -> AnyPublisher<String, Error> {
        let event = createExternalTrackingEvent(eventName: eventName,
                                                eventParams: eventParams,
                                                segmentationEventParamKeys: segmentationEventParamKeys)
        Logger.info("Firing External Tracking Event with: \n\(event)")
        return NotiflyAPI().trackEvent(event)
    }
    
    func trackInternalEvent(eventName: String,
                            params: [String: String]?,
                            segmentationEventParamKeys: [String]?) -> AnyPublisher<String, Error> {
        let pub = createInternalTrackingEvent(name: eventName,
                                              eventParams: params,
                                              segmentation_event_param_keys: segmentationEventParamKeys)
            .flatMap(NotiflyAPI().trackEvent)
            .eraseToAnyPublisher()
        
        Logger.info("Firing External Tracking Event")
        return pub
    }
    
    func createExternalTrackingEvent(eventName: String,
                                     eventParams: [String: String]?,
                                     segmentationEventParamKeys: [String]?) -> ExternalTrackingEvent {
        let userID = Notifly.main.userManager.externalUserID
        return ExternalTrackingEvent(projectID: projectID,
                                     eventName: eventName,
                                     isGlobalEvent: userID == nil,
                                     eventParams: eventParams,
                                     segmentationEventParamKeys: segmentationEventParamKeys,
                                     userID: userID)
    }
    
    func createInternalTrackingEvent(name: String,
                                     eventParams: [String: String]?,
                                     segmentation_event_param_keys: [String]?) -> AnyPublisher<InternalTrackingEvent, Error> {

        if let pub = Notifly.main.notificationsManager.apnDeviceTokenPub {
            return pub.tryMap { pushToken in
                InternalTrackingEvent(id: UUID().uuidString,
                                             name: name,
                                             notifly_user_id: try Notifly.main.userManager.getNotiflyUserID(),
                                             external_user_id: Notifly.main.userManager.externalUserID,
                                             time: Int(Date().timeIntervalSince1970),
                                             notifly_device_id: try AppHelper.getDeviceID(),
                                             external_device_id: try AppHelper.getDeviceID(),
                                             device_token: pushToken,
                                             is_internal_event: true,
                                             segmentation_event_param_keys: segmentation_event_param_keys,
                                             project_id: Notifly.main.projectID,
                                             platform: AppHelper.getDevicePlatform(),
                                             os_version: AppHelper.getiOSVersion(),
                                             app_version: try AppHelper.getAppVersion(),
                                             sdk_version: try AppHelper.getSDKVersion(),
                                             eventParams: eventParams)
            }.eraseToAnyPublisher()
        } else {
            return Fail(outputType: InternalTrackingEvent.self, failure: NotiflyError.unexpectedNil("APN Device Token is nil"))
                .eraseToAnyPublisher()
        }
    }
    
    // MARK: Private Methods
    
    func getDeviceID() throws -> String {
        if let deviceUUID = UIDevice.current.identifierForVendor {
            return deviceUUID.notiflyStyleString
        } else {
            throw NotiflyError.unexpectedNil("Failed to get the Device Identifier.")
        }
    }
}
