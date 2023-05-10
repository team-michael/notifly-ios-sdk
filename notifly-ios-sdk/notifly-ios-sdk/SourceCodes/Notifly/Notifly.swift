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
    let useCustomClickHandler: Bool
    let launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    let auth: Auth
    let notificationsManager: NotificationsManager
    let trackingManager: TrackingManager
    let userManager: UserManager

    var trackingCancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    init(
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        projectID: String,
        username: String,
        password: String,
        useCustomClickHandler: Bool
    ) {
        self.projectID = projectID
        self.useCustomClickHandler = useCustomClickHandler
        self.launchOptions = launchOptions

        auth = Auth(username: username,
                    password: password)
        notificationsManager = NotificationsManager()
        trackingManager = TrackingManager(projectID: projectID)
        userManager = UserManager()

        setup()
    }

    // MARK: - Private Methods

    private func setup() {
        if !useCustomClickHandler {
            UNUserNotificationCenter.current().delegate = notificationsManager
        }

        // handle cold start from push notification if cold start using launchOptions
        // if let launchOptions = launchOptions,
        //    let notification = launchOptions[.remoteNotification] as? UNNotification
        // {
        //     notificationsManager.handleNotificationClick(notification, clickStatus: "quit", completion: {})
        // }

    }
}
