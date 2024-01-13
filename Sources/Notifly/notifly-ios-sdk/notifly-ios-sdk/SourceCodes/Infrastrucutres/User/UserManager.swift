import Combine
import FirebaseMessaging
import Foundation

@available(iOSApplicationExtension, unavailable)
class UserManager {
    var externalUserID: String? {
        didSet { // TODO:
            if externalUserID == nil {
                _notiflyUserIDCache = nil
            }
        }
    }

    private var _notiflyUserIDCache: String?

    init() {
        externalUserID = NotiflyCustomUserDefaults.externalUserIdInUserDefaults
    }

    private func changeExternalUserId(newValue: String?) {
        _notiflyUserIDCache = nil
        externalUserID = newValue
        NotiflyCustomUserDefaults.externalUserIdInUserDefaults = newValue
    }

    func setExternalUserId(_ newExternalUserID: String?) {
        if newExternalUserID == nil {
            unregisteredUserId()
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

        guard externalUserID != newExternalUserID else {
            Logger.info("External User Id is not changed because the new user id is same as the current user id.")
            return
        }

        if let data = [
            TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID,
            TrackingConstant.Internal.previousExternalUserID: externalUserID,
            TrackingConstant.Internal.previousNotiflyUserID: try? getNotiflyUserID(),
        ] as? [String: Any] {
            let previousExternalUserID = externalUserID

            changeExternalUserId(newValue: newExternalUserID)

            let postProcessConfigForSyncState = constructPostProcessConfigForSyncState(previousExternalUserID: externalUserID, newExternalUserID: newExternalUserID)
            if shouldRequestSyncState(previousExternalUserID: previousExternalUserID, newExternalUserID: newExternalUserID) {
                notifly.inAppMessageManager.userStateManager.syncState(postProcessConfig: postProcessConfigForSyncState)
            }
            setUserProperties(data)

        } else {
            Logger.error("Fail to Set User Id.")
        }
    }

    private func unregisteredUserId() {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Remove User Id: Notifly is not initialized yet.")
            return
        }
        let previousExternalUserID = externalUserID

        changeExternalUserId(newValue: nil)
        let postProcessConfigForSyncState = constructPostProcessConfigForSyncState(previousExternalUserID: previousExternalUserID, newExternalUserID: nil)
        
        if shouldRequestSyncState(previousExternalUserID: previousExternalUserID, newExternalUserID: nil) {
            notifly.inAppMessageManager.userStateManager.syncState(postProcessConfig: postProcessConfigForSyncState)
        }

        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.removeUserPropertiesEventName, eventParams: nil)
    }

    func setUserProperties(_ userProperties: [String: Any]) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set User Properties: Notifly is not initialized yet.")
            return
        }
        notifly.inAppMessageManager.updateUserProperties(
            userID: try? getNotiflyUserID(),
            properties: userProperties
        )
        
        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.setUserPropertiesEventName, eventParams: userProperties)
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

    private func constructPostProcessConfigForSyncState(previousExternalUserID: String?, newExternalUserID: String?) -> PostProcessConfigForSyncState {
        return PostProcessConfigForSyncState(merge: shouldMergeStateAfterSyncState(previousExternalUserID: previousExternalUserID, newExternalUserID: newExternalUserID), clear: shouldClearStateAfterSyncState(newExternalUserID: newExternalUserID))
    }

    private func shouldMergeStateAfterSyncState(previousExternalUserID: String?, newExternalUserID _: String?) -> Bool {
        return externalUserID != nil && previousExternalUserID == nil
    }

    private func shouldClearStateAfterSyncState(newExternalUserID: String?) -> Bool {
        return newExternalUserID == nil
    }

    private func shouldRequestSyncState(previousExternalUserID: String?, newExternalUserID: String?) -> Bool {
        return newExternalUserID != previousExternalUserID
    }
}
