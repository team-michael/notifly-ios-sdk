import Foundation

enum NotiflySdkConfig {
    static let sdkVersion: String = "1.17.0"
    static var sdkWrapperVersion: String?
    static let sdkType: String = "native"
    static var sdkWrapperType: SdkWrapperType?
}

enum NotiflyConstant {
    static let iosPlatform: String = "ios"
    static let projectIdRegex: String = "^[0-9a-fA-F]{32}$"
    enum EndPoint {
        static let trackEventEndPoint =
            "https://e.notifly.tech/records"
        static let syncStateEndPoint = "https://api.notifly.tech/user-state"
        static let authorizationEndPoint = "https://api.notifly.tech/authorize"
    }
}

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
        static let setDevicePropertiesEventName = "set_device_properties"

        static let setUserPropertiesEventName = "set_user_properties"
        static let removeUserPropertiesEventName = "remove_external_user_id"

        static let notiflyExternalUserID = "external_user_id"
        static let notiflyUserID = "notifly_user_id"
        static let previousNotiflyUserID = "previous_notifly_user_id"
        static let previousExternalUserID = "previous_external_user_id"

        static let pushClickEventName = "push_click"
        static let pushNotificationMessageShown = "push_delivered"
        static let inAppMessageShown = "in_app_message_show"
        static let inAppMessageCloseButtonClicked = "close_button_click"
        static let inAppMessageMainButtonClicked = "main_button_click"
        static let inAppMessageDontShowAgainButtonClicked = "hide_in_app_message_button_click"
        static let inAppMessageSurveySubmitButtonClicked = "survey_submit_button_click"
    }

    enum InternalUserPropertyKey {
        static let phoneNumber = "$phone_number"
        static let email = "$email"
        static let timezone = "$timezone"
    }
}

enum TimeConstant {
    static let oneMinuteInSeconds = 60
    static let oneHourInSeconds = 60 * oneMinuteInSeconds
    static let oneDayInSeconds = 24 * oneHourInSeconds
    static let oneWeekInSeconds = 7 * oneDayInSeconds
    static let oneMonthInSeconds = 30 * oneDayInSeconds

    enum TimestampUnit: Int {
        case second = 1
        case microsecond = 1_000_000
    }
}

enum NotiflyValueType: String {
    case string = "TEXT"
    case int = "INT"
    case bool = "BOOL"
    case double = "DOUBLE"
    case array = "ARRAY"
    case cgFloat = "CGFLOAT"
}

struct NotiflyValue {
    let type: String?
    let value: Any?

    init?(type: String?, value: Any?) {
        guard let type = type else {
            return nil
        }

        self.type = type
        self.value = value
    }
}

enum NotiflyOperator: String {
    case isNull = "IS_NULL"
    case isNotNull = "IS_NOT_NULL"
    case equal = "="
    case notEqual = "<>"
    case contains = "@>"
    case greaterThan = ">"
    case greaterOrEqualThan = ">="
    case lessThan = "<"
    case lessOrEqualThan = "<="
}

enum NotiflyTriggeringConditonType: String {
    case eventName = "event_name"
}

enum NotiflyStringOperator: String {
    case equals = "="
    case notEquals = "!="
    case startsWith = "starts_with"
    case doesNotStartWith = "does_not_start_with"
    case endsWith = "ends_with"
    case doesNotEndWith = "does_not_end_with"
    case contains
    case doesNotContain = "does_not_contain"
    case matchesRegex = "matches_regex"
    case doesNotMatchRegex = "does_not_match_regex"
}
