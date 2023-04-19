
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
        let userID = Notifly.main.userManager.externalUserID
        let event = createTrackingEvent(eventName: eventName,
                                        eventParams: eventParams,
                                        segmentationEventParamKeys: segmentationEventParamKeys,
                                        userID: userID)
        return NotiflyAPI().trackEvent(event)
    }
    
    func trackInternalEvent(eventName: String,
                            params: [String: String]?,
                            segmentationEventParamKeys: [String]?) {
        
    }
    
    func createTrackingEvent(eventName: String,
                             eventParams: [String: String]?,
                             segmentationEventParamKeys: [String]?,
                             userID: String?) -> TrackingEvent {
        return TrackingEvent(projectID: projectID,
                             eventName: eventName,
                             isGlobalEvent: userID == nil,
                             eventParams: eventParams,
                             segmentationEventParamKeys: segmentationEventParamKeys,
                             userID: userID)
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
