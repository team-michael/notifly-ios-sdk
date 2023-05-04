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
    
    func setExternalUserID(_ newExternalUserID: String?) throws {
        if let newExternalUserID = newExternalUserID, !newExternalUserID.isEmpty {
            // `self.externalUserID` property is set in `setUserProperties` function.
            try setUserProperties([TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID])
        } else {
            externalUserID = nil
            Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.removeUserPropertiesEventName, params: nil)
        }
    }
    
    func setUserProperties(_ params: [String: String]) throws {
        var params = params
        if let newExternalUserID = params[TrackingConstant.Internal.notiflyExternalUserID] {
            params[TrackingConstant.Internal.previousExternalUserID] = externalUserID
            params[TrackingConstant.Internal.previousNotiflyUserID] = try getNotiflyUserID()
            
            externalUserID = newExternalUserID
            _notiflyUserIDCache = nil
        }
        Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.setUserPropertiesEventName, params: params)
    }
    
    func getNotiflyUserID() throws -> String {
        let userID = try _notiflyUserIDCache ?? generateUserID(externalUserID: externalUserID)
        _notiflyUserIDCache = userID
        return userID
    }
    
    private func generateUserID(externalUserID: String?) throws -> String {
        let projectID = Notifly.main.projectID
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
