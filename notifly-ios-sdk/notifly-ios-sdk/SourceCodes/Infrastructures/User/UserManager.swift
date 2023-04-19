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
        if let newExternalUserID = newExternalUserID {
            // `self.externalUserID` property is set in `setUserProperties` function.
            try setUserProperties([TrackingConstant.Internal.notiflyExternalUserID: newExternalUserID])
        } else {
            externalUserID = nil
            Notifly.main.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.removeUserPropertiesEventName,
                                                            params: nil,
                                                            segmentationEventParamKeys: nil)
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
        Notifly.main.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.setUserPropertiesEventName,
                                                        params: params,
                                                        segmentationEventParamKeys: nil)
    }
    
    func getNotiflyUserID() throws -> String {
        let userID = try _notiflyUserIDCache ?? generateUserID(externalUserID: externalUserID)
        _notiflyUserIDCache = userID
        return userID
    }
    
    private func generateUserID(externalUserID: String?) throws -> String {
        let projectID = Notifly.main.projectID
        let uuidV5Namespace: UUID?
        let uuidV5Name: String

        if let externalUserID = externalUserID {
            uuidV5Namespace = UUID(uuidString: "\(projectID)\(externalUserID)")
            uuidV5Name = TrackingConstant.Hash.registeredUserID
        } else {
            let deviceToken = try AppHelper.getDeviceID()
            uuidV5Namespace = UUID(uuidString: "\(projectID)\(deviceToken)")
            uuidV5Name = TrackingConstant.Hash.unregisteredUserID
        }
        
        guard let namespaceUUID = uuidV5Namespace,
              let uuidV5 = UUID(uuidString: "\(namespaceUUID.uuidString)\(uuidV5Name)")else {
            Logger.error("Failed to generate UserID with projectID: \(projectID), externalUserID: \(externalUserID ?? "null")")
            throw NotiflyError.unexpectedNil("Failed to generate UserID using UUID V5")
        }
        
        return uuidV5.notiflyStyleString
    }
}
