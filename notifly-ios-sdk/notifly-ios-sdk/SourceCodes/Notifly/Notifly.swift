import Combine
import Foundation
import UIKit

public class Notifly {

    static var main: Notifly {
        get {
            guard let notifly = _main else {
                fatalError("🔥 [Notifly Error] You must call `Notifly.initialize` before calling this method.")
            }
            return notifly
        } 
        set {
            _main = newValue
            isInitialized = true
            Logger.info("🚀 Notifly SDK initialized.")
        }
    }

    private static var _main: Notifly?
    static var isInitialized: Bool = false
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
