
import Foundation
protocol NotiflyApiRequestProtocol: Encodable {}

struct ApiRequestBody: NotiflyApiRequestProtocol {
    var payload: RequestPayload
    
    enum CodingKeys: String, CodingKey {
        case userName
        case password
        case records
    }
    
    init(payload: RequestPayload) {
        self.payload = payload
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch payload {
        case .TrackingEvent(let trackingEvent):
            try container.encode(trackingEvent.records, forKey: .records)
            
        case .AuthCredentials(let credentials):
            try container.encode(credentials.userName, forKey: .userName)
            try container.encode(credentials.password, forKey: .password)
        }
    }
    
   
}

enum RequestPayload: NotiflyApiRequestProtocol {
    case TrackingEvent(TrackingEvent)
    case AuthCredentials(Credentials)
    
    enum CodingKeys: String, CodingKey {
        case trackingEvent
        case authCredentials
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .TrackingEvent(let trackingEvent):
            try container.encode(trackingEvent, forKey: .trackingEvent)
        case .AuthCredentials(let credentials):
            try container.encode(credentials, forKey: .authCredentials)
        }
    }
}

struct TrackingEvent: Codable {
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
    let sdk_type: String
    let event_params: [String: AnyCodable]?
}

struct AnyCodable: Codable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let encodable = value as? Encodable {
            try encodable.encode(to: encoder)
        } else {
            try container.encodeNil()
        }
    }
    
    func getValue() -> Any {
        return self.value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue
        } else if let floatValue = try? container.decode(Float.self) {
            value = floatValue
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue
        } else if let arrayValue = try? container.decode([AnyCodable?].self) {
            value = arrayValue.compactMap { $0?.value }
        } else if container.decodeNil() {
            value = ()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }
}

public enum SdkWrapperType: String {
    case react_native
    case flutter
}
