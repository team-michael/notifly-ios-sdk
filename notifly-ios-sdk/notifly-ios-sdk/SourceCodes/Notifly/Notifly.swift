import Combine
import Foundation
import UIKit

public class Notifly {

    static var main: Notifly {
        get throws {
            guard let notifly = _main else {
                throw NotiflyError.notInitialized
            }
            return notifly
        } 
    }
    static var _main: Notifly?
    static var sdkVersion: String? = Bundle(for: Notifly.self).infoDictionary?["CFBundleShortVersionString"] as? String
    static var sdkType: SdkType = .native

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

public enum SdkType: String {
  case native = "native"
  case react_native = "react_native"
  case flutter = "flutter"
}
