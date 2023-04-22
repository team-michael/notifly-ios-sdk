
import Foundation

protocol TrackingEventProtocol: Codable {}

struct TrackingEvent: TrackingEventProtocol {
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
    let event_params: [String: String]?
}
