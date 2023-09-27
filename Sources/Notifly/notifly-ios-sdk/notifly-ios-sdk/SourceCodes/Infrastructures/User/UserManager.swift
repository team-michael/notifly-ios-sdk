import Combine
import FirebaseMessaging
import Foundation

class UserManager {
    
    var externalUserID: String? {
        didSet {
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
        self._notiflyUserIDCache = nil
        externalUserID = newValue
        NotiflyCustomUserDefaults.externalUserIdInUserDefaults = newValue
    }
    
    private func shouldMergeStateSynchronized() -> Bool {
        return externalUserID == nil
    }
    
    func setExternalUserId(_ newExternalUserID: String?) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set or Remove User Id: Notifly is not initialized yet.")
            return
        }
        
        if let newExternalUserID = newExternalUserID,
            !newExternalUserID.isEmpty,
            let data = [
                TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID,
                TrackingConstant.Internal.previousExternalUserID: externalUserID,
                TrackingConstant.Internal.previousNotiflyUserID: try? getNotiflyUserID(),
            ] as? [String: Any] {
            let shouldMergeState = shouldMergeStateSynchronized()
            changeExternalUserId(newValue: newExternalUserID)
            notifly.inAppMessageManager.syncState(merge: shouldMergeState)
            setUserProperties(data)
        }
        else {
            self.changeExternalUserId(newValue: nil)
            notifly.inAppMessageManager.syncState(merge: false)
            notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.removeUserPropertiesEventName, eventParams: nil)
        }
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
        let projectID = notifly.projectID
        let uuidV5Namespace: UUID
        let uuidV5Name: String

        if let externalUserID = externalUserID {
            uuidV5Name = "\(projectID)\(externalUserID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.registeredUserID
        } else {
            let deviceID = try AppHelper.getDeviceID()
            uuidV5Name = "\(projectID)\(deviceID)"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }
        
        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }
}
