import Foundation

enum TrackingConstant {
    
    enum Hash {
        static let eventID = "830b5f7b-e392-43db-a17b-d835f0bcab2b"
        static let registeredUserID = "ce7c62f9-e8ae-4009-8fd6-468e9581fa21"
        static let unregisteredUserID = "a6446dcf-c057-4de7-a360-56af8659d52f"
        static let deviceID = "830848b3-2444-467d-9cd8-3430d2738c57"
    }
    
    enum Internal {
        
        // MARK: Session
        
        static let sessionStartEventName = "session_start"
        
        // MARK: User Properties

        static let setUserPropertiesEventName = "set_user_properties"
        static let removeUserPropertiesEventName = "remove_external_user_id"
        static let notiflyExternalUserID = "notiflyExternalUserId"
        static let notiflyUserID = "notifly_user_id"
        static let previousNotiflyUserID = "previous_notifly_user_id"
        static let previousExternalUserID = "previous_external_user_id"
        static let setUserProperties = "set_user_properties"
        
        // MARK: Push Notification Handlling
        
        static let pushClickEventName = "push_click"
        static let pushNotificationMessageShown = "in_app_message_show"
    }
}
