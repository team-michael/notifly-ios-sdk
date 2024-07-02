import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
@objc public class Notifly: NSObject {
    private static var _main: Notifly?
    static var main: Notifly {
        get throws {
            guard let notifly = _main else {
                throw NotiflyError.notInitialized
            }
            return notifly
        }
    }

    private static var _asyncWorker = NotiflyAsyncWorker()
    static var asyncWorker: NotiflyAsyncWorker {
        get {
            _asyncWorker
        }
    }

    static var coldStartNotificationData: [AnyHashable: Any]?
    static var inAppMessageDisabled: Bool = false

    private let cancellablesAccessQueue = DispatchQueue(label: "com.notifly.manager.access.queue")
    private var cancellables = Set<AnyCancellable>()

    let projectId: String
    let auth: Auth
    let notificationsManager: NotificationsManager
    let trackingManager: TrackingManager
    let userManager: UserManager
    let inAppMessageManager: InAppMessageManager

    // MARK: Lifecycle

    init(
        projectId: String,
        username: String,
        password: String
    ) {
        self.projectId = projectId
        NotiflyCustomUserDefaults.register(projectId: projectId, org: username)
        NotiflyCustomUserDefaults.projectIdInUserDefaults = projectId
        NotiflyCustomUserDefaults.usernameInUserDefaults = username
        NotiflyCustomUserDefaults.passwordInUserDefaults = password

        auth = Auth(
            username: username,
            password: password)
        trackingManager = TrackingManager(projectId: projectId)
        userManager = UserManager()

        notificationsManager = NotificationsManager()
        inAppMessageManager = InAppMessageManager(owner: (try? userManager.getNotiflyUserID()))
        super.init()
    }

    func storeCancellable(cancellable: AnyCancellable) {
        cancellablesAccessQueue.async {
            cancellable.store(in: &self.cancellables)
        }
    }

    static func setup(
        projectId: String,
        username: String,
        password: String
    ) {
        _main = Notifly(
            projectId: projectId,
            username: username,
            password: password
        )
    }
}
