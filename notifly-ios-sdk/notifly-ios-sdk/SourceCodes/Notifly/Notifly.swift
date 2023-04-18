
import Foundation
import Combine
import UIKit

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
            Logger.info("Notifly initialized with projectID: \(newValue.projectID)")
        }
    }

    static private var _main: Notifly?

    
    let projectID: String
    let useCustomClickHandler: Bool
    
    let auth: Auth
    let notificationsManager: NotificationsManager
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
        self.notificationsManager = NotificationsManager()
        self.trackingManager = TrackingManager(projectID: projectID)
        setup()
    }
    
    private func setup() {
        UNUserNotificationCenter.current().delegate = notificationsManager
    }
}
