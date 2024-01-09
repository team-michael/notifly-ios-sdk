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

        guard let newExternalUserID = newExternalUserID as? String,
              !newExternalUserID.isEmpty,
              externalUserID != newExternalUserID
        else {
            Logger.info("External User Id is not changed because the new user id is same as the current user id.")
            return
        }

        if let data = [
            TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID,
            TrackingConstant.Internal.previousExternalUserID: externalUserID,
            TrackingConstant.Internal.previousNotiflyUserID: try? getNotiflyUserID(),
        ] as? [String: Any] {
            let shouldMergeState = shouldMergeStateSynchronized()
            changeExternalUserId(newValue: newExternalUserID)
            notifly.inAppMessageManager.syncState(merge: shouldMergeState, clear: false)
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
        changeExternalUserId(newValue: nil)
        notifly.inAppMessageManager.syncState(merge: false, clear: true)
        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.removeUserPropertiesEventName, eventParams: nil)
    }

    func setUserProperties(_ userProperties: [String: Any]) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set User Properties: Notifly is not initialized yet.")
            return
        }
        notifly.inAppMessageManager.updateUserProperties(properties: userProperties)
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

    private func shouldMergeStateSynchronized() -> Bool {
        return externalUserID == nil
    }
}
