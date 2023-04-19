
import Foundation

struct TrackingEvent: Codable {
    
    /// Notifly 팀에서 제공드리는 project ID 입니다. 문의 사항은 contact@workmichael.com 으로 이메일 부탁드립니다.
    let projectID: String
    /// 이벤트명
    let eventName: String
    /// 특정 유저에게만 발생하는 것이 아니라 서비스 레벨에서 발생하는 이벤트인지의 여부
    let isGlobalEvent: Bool
    /// 이벤트 파라미터 값들
    let eventParams: [String: String]?
    /// 정교한 캠페인 집행을 위해 특정 파라미터들을 notifly 엔진에서 특수하게 처리합니다. 문의 사항은 contact@workmichael.com 으로 이메일 부탁드립니다.
    let segmentationEventParamKeys: [String]?
    /// 유저 ID
    let userID: String?
}

struct InternalTrackingEvent: Codable {
    let id: String
    let name: String
    let notifly_user_id: String
    let external_user_id: String?
    let time: Int
    let notifly_device_id: String
    let external_device_id: String
    let device_token: String
    let is_internal_event: Bool
    let segmentation_event_param_keys: [String]?
    let project_id: String
    let platform: String
    let os_version: String
    let app_version: String
    let sdk_version: String
    
    init(id: String,
         name: String,
         notifly_user_id: String,
         external_user_id: String?,
         time: Int,
         notifly_device_id: String,
         external_device_id: String,
         device_token: String,
         is_internal_event: Bool,
         segmentation_event_param_keys: [String]?,
         project_id: String,
         platform: String,
         os_version: String,
         app_version: String,
         sdk_version: String) {
        self.id = id
        self.name = name
        self.notifly_user_id = notifly_user_id
        self.external_user_id = external_user_id
        self.time = time
        self.notifly_device_id = notifly_device_id
        self.external_device_id = external_device_id
        self.device_token = device_token
        self.is_internal_event = is_internal_event
        self.segmentation_event_param_keys = segmentation_event_param_keys
        self.project_id = project_id
        self.platform = platform
        self.os_version = os_version
        self.app_version = app_version
        self.sdk_version = sdk_version
    }
    
    static func create(name: String,
                       notifly_user_id: String,
                       external_user_id: String?,
                       device_token: String,
                       segmentation_event_param_keys: [String]?) async throws -> InternalTrackingEvent {
        guard let pushToken = try await Notifly.main.notificationsManager.apnDeviceTokenPub?.value else {
            throw NotiflyError.unexpectedNil("APN Device Token is nil")
        }
        return InternalTrackingEvent(id: UUID().uuidString,
                                     name: name,
                                     notifly_user_id: notifly_user_id,
                                     external_user_id: external_user_id,
                                     time: Int(Date().timeIntervalSince1970),
                                     notifly_device_id: try AppHelper.getDeviceID(),
                                     external_device_id: try AppHelper.getDeviceID(),
                                     device_token: pushToken,
                                     is_internal_event: true,
                                     segmentation_event_param_keys: segmentation_event_param_keys,
                                     project_id: Notifly.main.projectID,
                                     platform: AppHelper.getDevicePlatform(),
                                     os_version: AppHelper.getiOSVersion(),
                                     app_version: try AppHelper.getAppVersion(),
                                     sdk_version: try AppHelper.getSDKVersion())
    }
}
