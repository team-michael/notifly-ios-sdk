import Combine
import Foundation
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

    private static var _main: Notifly?

    let projectID: String

    let auth: Auth
    let notificationsManager: NotificationsManager
    let trackingManager: TrackingManager
    let userManager: UserManager

    var trackingCancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    init(
        projectID: String,
        username: String,
        password: String
    ) {
        self.projectID = projectID

        auth = Auth(username: username,
                    password: password)
        notificationsManager = NotificationsManager()
        trackingManager = TrackingManager(projectID: projectID)
        userManager = UserManager()

    }

}
