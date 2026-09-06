import Combine
@_implementationOnly import FirebaseMessaging
import Foundation
@_implementationOnly import NotiflyKMP

@available(iOSApplicationExtension, unavailable)
class UserManager {
    private let userIdAccessQueue = DispatchQueue(
        label: "com.notifly.userManager.changeExternalUserIdQueue"
    )

    private var _notiflyUserIDCache: String?
    var notiflyUserIDCache: String? {
        get {
            userIdAccessQueue.sync {
                _notiflyUserIDCache
            }
        }
        set {
            userIdAccessQueue.sync {
                _notiflyUserIDCache = newValue
            }
        }
    }

    private var _externalUserID: String?
    var externalUserID: String? {
        get {
            userIdAccessQueue.sync {
                _externalUserID
            }
        }
        set {
            userIdAccessQueue.sync {
                _externalUserID = newValue
            }
        }
    }

    init() {
        externalUserID = NotiflyCustomUserDefaults.externalUserIdInUserDefaults
    }

    func changeExternalUserId(newValue: String?) {
        notiflyUserIDCache = nil
        externalUserID = newValue
        userIdAccessQueue.async {
            NotiflyCustomUserDefaults.externalUserIdInUserDefaults = newValue
        }
    }

    func setExternalUserId(_ newExternalUserID: String?) {
        if newExternalUserID == nil {
            handleRemoveExternalUserId()
            return
        }

        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set User Id: Notifly is not initialized yet.")
            return
        }

        guard let newExternalUserID = newExternalUserID,
            !newExternalUserID.isEmpty
        else {
            Logger.error("Fail to Set User Id.")
            return
        }

        if let data = [
            TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID,
            TrackingConstant.Internal.previousExternalUserID: externalUserID,
            TrackingConstant.Internal.previousNotiflyUserID: try? getNotiflyUserID()
        ] as? [String: Any] {
            Notifly.asyncWorker.addTask { [weak self] finishTask in
                guard let self = self else {
                    finishTask()
                    return
                }

                let transition = UserIdTransitionPolicy.shared.evaluate(
                    previousUserId: externalUserID,
                    newUserId: newExternalUserID
                )
                guard transition.changed else {
                    Logger.info(
                        "External User Id is not changed because the new user id is same as the current user id."
                    )
                    finishTask()
                    return
                }

                self.changeExternalUserId(newValue: newExternalUserID)
                let postProcessConfigForSyncState = PostProcessConfigForSyncState(
                    merge: transition.shouldMerge,
                    clear: transition.shouldClear
                )
                if transition.shouldSync {
                    notifly.inAppMessageManager.userStateManager.syncState(
                        postProcessConfig: postProcessConfigForSyncState
                    ) {
                        self.setUserProperties(userProperties: data, lockAcquired: true)
                        finishTask()
                    }
                } else {
                    self.setUserProperties(userProperties: data, lockAcquired: true)
                    finishTask()
                }
            }

        } else {
            Logger.error("Fail to Set User Id.")
        }
    }

    private func handleRemoveExternalUserId() {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Remove User Id: Notifly is not initialized yet.")
            return
        }

        Notifly.asyncWorker.addTask { [weak self] finishTask in
            guard let self = self else {
                finishTask()
                return
            }
            let previousExternalUserID = externalUserID
            let transition = UserIdTransitionPolicy.shared.evaluate(
                previousUserId: previousExternalUserID,
                newUserId: nil
            )
            self.changeExternalUserId(newValue: nil)

            let postProcessConfigForSyncState = PostProcessConfigForSyncState(
                merge: transition.shouldMerge,
                clear: transition.shouldClear
            )
            if transition.shouldSync {
                notifly.inAppMessageManager.userStateManager.syncState(
                    postProcessConfig: postProcessConfigForSyncState
                ) {
                    notifly.trackingManager.trackInternalEvent(
                        eventName: TrackingConstant.Internal.removeUserPropertiesEventName,
                        eventParams: nil,
                        lockAcquired: true
                    )
                    finishTask()
                }
            } else {
                notifly.inAppMessageManager.userStateManager.clear()
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.removeUserPropertiesEventName,
                    eventParams: nil,
                    lockAcquired: true
                )
                finishTask()
            }
        }
    }

    func setUserProperties(userProperties: [String: Any], lockAcquired: Bool = false) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set User Properties: Notifly is not initialized yet.")
            return
        }

        if !Notifly.inAppMessageDisabled {
            Notifly.asyncWorker.addTask { [weak self] finishTask in
                guard let self = self else {
                    finishTask()
                    return
                }
                notifly.inAppMessageManager.userStateManager.updateUserData(
                    userID: try? getNotiflyUserID(),
                    properties: userProperties
                )
                finishTask()
            }
        }

        notifly.trackingManager.trackInternalEvent(
            eventName: TrackingConstant.Internal.setUserPropertiesEventName,
            eventParams: userProperties,
            lockAcquired: lockAcquired
        )
    }

    func getNotiflyUserID() throws -> String {
        let userID = try (_notiflyUserIDCache ?? generateUserID(externalUserID: externalUserID))
        _notiflyUserIDCache = userID
        return userID.lowercased()
    }

    private func generateUserID(externalUserID: String?) throws -> String {
        guard let notifly = try? Notifly.main else {
            throw NotiflyError.notInitialized
        }
        let projectId = notifly.projectId
        let uuidV5Namespace: UUID
        let uuidV5Name: String

        if let externalUserID = externalUserID {
            uuidV5Name = "\(projectId)\(externalUserID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.registeredUserID
        } else {
            let deviceID = try AppHelper.getDeviceID()
            uuidV5Name = "\(projectId)\(deviceID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }

        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }

}
