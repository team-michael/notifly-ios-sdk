import Foundation
import Combine

/**
 Contains all available Notifly SDK Public APIs.
 */
public extension Notifly {
    
    static func initialize(projectID: String,
                           username: String,
                           password: String,
                           useCustomClickHandler: Bool) {
        main = Notifly(projectID: projectID,
                       username: username,
                       password: password,
                       useCustomClickHandler: useCustomClickHandler)
    }
    
    static func track(eventName: String,
                      eventParams: [String: String],
                      segmentationEventParamKeys: [String],
                      userID: String?) -> AnyPublisher<String, Error> {
        return main.track(eventName: eventName,
                          eventParams: eventParams,
                          segmentationEventParamKeys: segmentationEventParamKeys,
                          userID: userID)
    }
}
