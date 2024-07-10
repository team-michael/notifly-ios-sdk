import Foundation

struct NotiflyAnyCodable: Codable {
    private var value: Any?
    init(_ value: Any?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([NotiflyAnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: NotiflyAnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let value = value else {
            try container.encodeNil()
            return
        }
        if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let arrayValue = value as? [Any?] {
            let encodableArray = arrayValue.map { NotiflyAnyCodable($0) }
            try container.encode(encodableArray)
        } else if let dictionaryValue = value as? [String: Any?] {
            let encodableDictionary = dictionaryValue.mapValues { NotiflyAnyCodable($0) }
            try container.encode(encodableDictionary)
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }

    static func parseJsonString(_ jsonString: String) -> [String: Any]? {
        let decoder = JSONDecoder()
        if let jsonData = jsonString.data(using: .utf8),
            let decodedData = try? decoder.decode(
                NotiflyAnyCodable.self, from: jsonData
            ),
            let value = decodedData.value as? [String: Any]
        {
            return value
        }
        return nil
    }

}
