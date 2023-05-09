
import Foundation

protocol TrackingEventProtocol: Codable {}

struct TrackingEvent: TrackingEventProtocol {
    let records: [TrackingRecord]
}

struct TrackingRecord: Codable {
    let partitionKey: String
    let data: String?
}

struct TrackingData: Codable {
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
    let event_params: [TrackingDataEventParam]?
}


struct TrackingDataEventParam: Codable {
    let key: String
    var value: Any

    enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    init(key: String, value: Any) {
        self.key = key
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)

        // Decode the value based on its type
        if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = intValue
        } else if let boolValue = try? container.decode(Bool.self, forKey: .value) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .value) {
            value = stringValue
        } else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Unsupported value type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)

        // Encode the value based on its type
        switch value {
        case let intValue as Int:
            try container.encode(intValue, forKey: .value)
        case let boolValue as Bool:
            try container.encode(boolValue, forKey: .value)
        case let stringValue as String:
            try container.encode(stringValue, forKey: .value)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [CodingKeys.value], debugDescription: "Unsupported value type"))
        }
    }
}
