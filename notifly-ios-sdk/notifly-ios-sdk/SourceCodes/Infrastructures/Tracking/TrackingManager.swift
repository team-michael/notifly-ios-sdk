
import Foundation
import Combine

class TrackingManager {
    
    private let projectID: String
    
    init(projectID: String) {
        self.projectID = projectID
    }
    
    func track(eventName: String, eventParams: [String: String], segmentationEventParamKeys: [String], userID: String?) -> AnyPublisher<String, Error> {
        let event = TrackingEvent(projectID: projectID,
                                  eventName: eventName,
                                  isGlobalEvent: userID == nil,
                                  eventParams: eventParams,
                                  segmentationEventParamKeys: segmentationEventParamKeys,
                                  userID: userID)
        return NotiflyAPI().trackEvent(event)
    }
}
