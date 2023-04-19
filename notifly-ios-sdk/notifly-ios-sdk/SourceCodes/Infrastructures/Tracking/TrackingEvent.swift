
import Foundation

protocol TrackingEventProtocol: Codable {}

struct ExternalTrackingEvent: TrackingEventProtocol {
    
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

struct InternalTrackingEvent: TrackingEventProtocol {
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
    let eventParams: [String: String]?
}
