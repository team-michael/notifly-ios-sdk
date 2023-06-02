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
    
    func setExternalUserId(_ newExternalUserID: String?) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set or Remove User Id: Notifly is not initialized yet.")
            return
        }
        if let newExternalUserID = newExternalUserID, !newExternalUserID.isEmpty {
            // `self.externalUserID` property is set in `setUserProperties` function.
            setUserProperties([TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID])
        } else {
            externalUserID = nil
            NotiflyCustomUserDefaults.externalUserIdInUserDefaults = nil
            notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.removeUserPropertiesEventName, eventParams: nil)
        }
    }
    
    func setUserProperties(_ userProperties: [String: Any]) {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Set User Properties: Notifly is not initialized yet.")
            return
        }
        var userProperties = userProperties
        if let newExternalUserID = userProperties[TrackingConstant.Internal.notiflyExternalUserID] as? String {
            userProperties[TrackingConstant.Internal.previousExternalUserID] = externalUserID
            userProperties[TrackingConstant.Internal.previousNotiflyUserID] = try? getNotiflyUserID()
            
            externalUserID = newExternalUserID
            NotiflyCustomUserDefaults.externalUserIdInUserDefaults = newExternalUserID
            _notiflyUserIDCache = nil
        }
        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.setUserPropertiesEventName, eventParams: userProperties)
    }
    
    func getNotiflyUserID() throws -> String {
        let userID = try (_notiflyUserIDCache ?? generateUserID(externalUserID: externalUserID))
        _notiflyUserIDCache = userID
        return userID
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
            let deviceToken = try AppHelper.getDeviceID()
            uuidV5Name = "\(projectID)\(deviceToken)"
            uuidV5Namespace = TrackingConstant.HashNamespace.unregisteredUserID
        }
        
        let uuidV5 = UUID(name: uuidV5Name, namespace: uuidV5Namespace)
        return uuidV5.notiflyStyleString
    }
}
