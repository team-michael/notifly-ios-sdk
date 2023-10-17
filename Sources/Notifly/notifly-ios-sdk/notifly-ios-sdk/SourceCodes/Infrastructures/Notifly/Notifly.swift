import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
@objc public class Notifly: NSObject {
    static var main: Notifly {
        get throws {
            guard let notifly = _main else {
                throw NotiflyError.notInitialized
            }
            return notifly
        }
    }

    static var _main: Notifly?
    static var sdkVersion: String = NotiflyConstant.sdkVersion
    static var sdkType: SdkType = .native
    static var coldStartNotificationData: [AnyHashable: Any]?
    static var inAppMessageDisabled: Bool = false

    let projectID: String

    let auth: Auth
    let notificationsManager: NotificationsManager
    let trackingManager: TrackingManager
    let userManager: UserManager
    let inAppMessageManager: InAppMessageManager

    var trackingCancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    init(
        projectID: String,
        username: String,
        password: String
    ) {
        self.projectID = projectID
        NotiflyCustomUserDefaults.projectIdInUserDefaults = projectID
        NotiflyCustomUserDefaults.usernameInUserDefaults = username
        NotiflyCustomUserDefaults.passwordInUserDefaults = password
        auth = Auth(username: username,
                    password: password)
        trackingManager = TrackingManager(projectID: projectID)
        userManager = UserManager()

        notificationsManager = NotificationsManager()
        inAppMessageManager = InAppMessageManager(disabled: Notifly.inAppMessageDisabled)
        super.init()
        Notifly._main = self
    }
}

public enum SdkType: String {
    case native
    case react_native
    case flutter
}
