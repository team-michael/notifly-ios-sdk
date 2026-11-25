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
        NotiflyStore.externalUserID
    }

    /// Persists synchronously on the caller, including URLSession response callbacks.
    @discardableResult
    func changeExternalUserId(newValue: String?) -> Bool {
        do {
            try NotiflyStore.setExternalUserID(newValue)
            lastUserPropertiesSentAt = nil
            notiflyUserIDCache = nil
            return true
        }
        catch {
            Logger.error("Cannot persist user identity; user change skipped: \(error)")
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

                guard changeExternalUserId(newValue: newExternalUserID) else {
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
                }
                else {
                    setUserProperties(userProperties: data, lockAcquired: true)
                    finishTask()
                }
            }

        }
        else {
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
            guard changeExternalUserId(newValue: nil) else {
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
            }
            else {
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

            if let lastUserPropertiesSentAt = lastUserPropertiesSentAt,
                (0..<5).contains(Date().timeIntervalSince1970 - lastUserPropertiesSentAt),
                !Notifly.inAppMessageDisabled,
                let userID = try? getNotiflyUserID(),
                let existing = notifly.inAppMessageManager.userStateManager.getUserData(userID: userID)?.userProperties,
                let previous = try? JSONSerialization.data(withJSONObject: existing.filter { userProperties.keys.contains($0.key) }, options: [.sortedKeys]),
                let incoming = try? JSONSerialization.data(withJSONObject: userProperties, options: [.sortedKeys]),
                previous == incoming
            {
                return
            }

            if !Notifly.inAppMessageDisabled {
                notifly.inAppMessageManager.userStateManager.updateUserData(
                    userID: try? getNotiflyUserID(),
                    properties: userProperties
                )
            }

            if userProperties[TrackingConstant.Internal.notiflyExternalUserID] == nil {
                lastUserPropertiesSentAt = Date().timeIntervalSince1970
            }
            notifly.trackingManager.trackInternalEvent(
                eventName: TrackingConstant.Internal.setUserPropertiesEventName,
                eventParams: userProperties,
                lockAcquired: true
            )
        }
    }

    /// Cold reads and pending identity writes may block the calling thread, including main.
    func getNotiflyUserID() throws -> String {
        let identity = try NotiflyStore.loadIdentity()
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
        }
        else {
            let deviceID = identity.deviceID
            // Keep the legacy optional representation to preserve existing anonymous user IDs.
            uuidV5Name = "\(projectId)\(String(describing: deviceID))"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }

        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }

}
