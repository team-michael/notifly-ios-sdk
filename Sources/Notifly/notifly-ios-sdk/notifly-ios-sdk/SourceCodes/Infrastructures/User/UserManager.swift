import Combine
import FirebaseMessaging
import Foundation
import NotiflyCore

@available(iOSApplicationExtension, unavailable)
class UserManager {
    private var lastUserPropertiesSentAt: TimeInterval?
    private let userIdAccessQueue = DispatchQueue(
        label: "com.notifly.userManager.changeExternalUserIdQueue"
    )

    private var _notiflyUserIDCache: String?
    private var cachedIdentity: StoredIdentity?
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

    var externalUserID: String? {
        NotiflyCustomUserDefaults.externalUserIdInUserDefaults
    }

    /// Persists on the caller, including network callbacks; no worker is scheduled.
    @discardableResult
    func changeExternalUserId(newValue: String?) -> Bool {
        guard let store = NotiflyCustomUserDefaults.identityStore else { return false }
        do {
            try store.setExternalUserID(newValue)
            self.lastUserPropertiesSentAt = nil
            self.notiflyUserIDCache = nil
            return true
        } catch {
            Logger.error("Cannot persist user identity; user switch skipped: \(error)")
            return false
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

        Notifly.asyncWorker.addTask { [weak self] finishTask in
            guard let self = self else {
                finishTask()
                return
            }
            // Capture the previous identity only after migration has completed.
            let previousExternalUserID = self.externalUserID
            let transition = UserIdTransitionPolicy.shared.evaluate(
                previousUserId: previousExternalUserID,
                newUserId: newExternalUserID
            )
            guard transition.changed else {
                Logger.info(
                    "External User Id is not changed because the new user id is same as the current user id."
                )
                finishTask()
                return
            }
            let data: [String: Any] = [
                TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID,
                TrackingConstant.Internal.previousExternalUserID: previousExternalUserID,
                TrackingConstant.Internal.previousNotiflyUserID: try? self.getNotiflyUserID(),
            ].compactMapValues { $0 }
            guard self.changeExternalUserId(newValue: newExternalUserID) else {
                finishTask()
                return
            }
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
            guard self.changeExternalUserId(newValue: nil) else {
                finishTask()
                return
            }
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

        Notifly.asyncWorker.addTask(lockAcquired: lockAcquired) { [weak self] finishTask in
            defer { finishTask() }
            guard let self = self else { return }

            if let lastUserPropertiesSentAt = self.lastUserPropertiesSentAt,
               (0..<5).contains(Date().timeIntervalSince1970 - lastUserPropertiesSentAt),
               !Notifly.inAppMessageDisabled,
               let userID = try? self.getNotiflyUserID(),
               let existing = notifly.inAppMessageManager.userStateManager.getUserData(userID: userID)?.userProperties,
               let previous = try? JSONSerialization.data(withJSONObject: existing.filter { userProperties.keys.contains($0.key) }, options: [.sortedKeys]),
               let incoming = try? JSONSerialization.data(withJSONObject: userProperties, options: [.sortedKeys]),
               previous == incoming {
                return
            }

            if !Notifly.inAppMessageDisabled {
                notifly.inAppMessageManager.userStateManager.updateUserData(
                    userID: try? self.getNotiflyUserID(),
                    properties: userProperties
                )
            }

            if userProperties[TrackingConstant.Internal.notiflyExternalUserID] == nil {
                self.lastUserPropertiesSentAt = Date().timeIntervalSince1970
            }
            notifly.trackingManager.trackInternalEvent(
                eventName: TrackingConstant.Internal.setUserPropertiesEventName,
                eventParams: userProperties,
                lockAcquired: true
            )
        }
    }

    /// Reads the identity on the calling thread. A cache miss or an in-flight storage
    /// operation may block, including when this method is called from the main thread.
    func getNotiflyUserID() throws -> String {
        let identity = try NotiflyCustomUserDefaults.loadIdentity()
        return userIdAccessQueue.sync {
            if cachedIdentity != identity { _notiflyUserIDCache = nil }
            let userID = _notiflyUserIDCache ?? generateUserID(identity: identity)
            _notiflyUserIDCache = userID
            cachedIdentity = identity
            return userID.lowercased()
        }
    }

    private func generateUserID(identity: StoredIdentity) -> String {
        let projectId = identity.projectID
        let uuidV5Namespace: UUID
        let uuidV5Name: String

        if let externalUserID = identity.externalUserID {
            uuidV5Name = "\(projectId)\(externalUserID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.registeredUserID
        } else {
            // Older releases interpolated a String? here. Preserve its Optional("...")
            // representation: unwrapping it would change every anonymous Notifly user ID.
            let legacyDeviceDescription = String(describing: Optional(identity.deviceID))
            uuidV5Name = "\(projectId)\(legacyDeviceDescription)"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }

        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }

}
