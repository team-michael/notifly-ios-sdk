
import Foundation
import Combine

public class Notifly {
    
    // MARK: - Properties
    
    static var main: Notifly {
        get {
            guard let notifly = _main else {
                fatalError("You must call `Notifly.initialize`.")
            }
            return notifly
        }
        set {
            _main = newValue
        }
    }

    static private var _main: Notifly?

    
    let projectID: String
    let useCustomClickHandler: Bool
    
    let auth: Auth
    let trackingManager: TrackingManager
    
    // MARK: Lifecycle
    
    init(projectID: String,
         username: String,
         password: String,
         useCustomClickHandler: Bool) {
        
        self.projectID = projectID
        self.useCustomClickHandler = useCustomClickHandler
        self.auth = Auth(username: username,
                         password: password)
        self.trackingManager = TrackingManager(projectID: projectID)
    }
    
    // MARK: Public Static Methods

    
    // MARK: Instance Methods
    
    func track(eventName: String,
               eventParams: [String: String],
               segmentationEventParamKeys: [String],
               userID: String?) -> AnyPublisher<String, Error> {
        return trackingManager.track(eventName: eventName,
                                     eventParams: eventParams,
                                     segmentationEventParamKeys: segmentationEventParamKeys,
                                     userID: userID)
    }
}
