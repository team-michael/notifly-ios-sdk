import Foundation

enum TrackingConstant {
    
    enum HashNamespace {
        static let eventID = UUID(uuidString: "830b5f7b-e392-43db-a17b-d835f0bcab2b")!
        static let registeredUserID = UUID(uuidString: "ce7c62f9-e8ae-4009-8fd6-468e9581fa21")!
        static let unregisteredUserID = UUID(uuidString: "a6446dcf-c057-4de7-a360-56af8659d52f")!
        static let deviceID = UUID(uuidString: "830848b3-2444-467d-9cd8-3430d2738c57")!
    }
    
    enum Internal {
        
        // MARK: Session
        
        static let sessionStartEventName = "session_start"
        
        // MARK: User Properties

        static let setUserPropertiesEventName = "set_user_properties"
        static let removeUserPropertiesEventName = "remove_external_user_id"
        static let notiflyExternalUserID = "external_user_id"
        static let notiflyUserID = "notifly_user_id"
        static let previousNotiflyUserID = "previous_notifly_user_id"
        static let previousExternalUserID = "previous_external_user_id"
        static let setUserProperties = "set_user_properties"
        
        // MARK: Push Notification Handlling
        
        static let pushClickEventName = "push_click"
        static let pushNotificationMessageShown = "push_delivered"
        static let inAppMessageShown = "in_app_message_show"
        static let inAppMessageCloseButtonClicked = "close_button_click"
        static let inAppMessageMainButtonClicked = "main_button_click"
        static let inAppMessageDontShowAgainButtonClicked = "hide_in_app_message_button_click"
    }
}
