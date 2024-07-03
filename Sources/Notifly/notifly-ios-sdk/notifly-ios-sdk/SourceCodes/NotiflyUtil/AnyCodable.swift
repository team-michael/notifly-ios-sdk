import Foundation

public struct AnyCodable: Codable {
    private let value: Any?

    init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let encodable = value as? Encodable {
            try encodable.encode(to: encoder)
        } else {
            try container.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let floatValue = try? container.decode(Float.self) {
            value = floatValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue
        } else if container.decodeNil() {
            value = nil
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    static func makeJsonCodable(_ jsonData: [String: Any]?) -> [String: AnyCodable]? {
        guard let jsonData = jsonData else { return nil }
        return jsonData.mapValues { value in
            if let array = value as? [Any?] {
                return AnyCodable(array.compactMap { element in self.toCodableValue(element) })
            } else if let dictionary = value as? [String: Any] {
                return AnyCodable(makeJsonCodable(dictionary))
            }
            return self.toCodableValue(value)
        }
    }

    static func toCodableValue(_ value: Any?) -> AnyCodable {
        if let str = value as? String {
            return AnyCodable(str)
        } else if let int = value as? Int {
            return AnyCodable(int)
        } else if let double = value as? Double {
            return AnyCodable(double)
        } else if let float = value as? Float {
            return AnyCodable(float)
        } else if let bool = value as? Bool {
            return AnyCodable(bool)
        } else {
            return AnyCodable(value)
        }
    }

    func getValue() -> Any {
        if let str = self.value as? String {
            return str
        } else if let int = self.value as? Int {
            return int
        } else if let double = self.value as? Double {
            return double
        } else if let float = self.value as? Float {
            return float
        } else if let bool = self.value as? Bool {
            return bool
        } else if let array = self.value as? [AnyCodable] {
            return array.map { element in element.getValue() }
        } else if let dictionary = self.value as? [String: AnyCodable] {
            return dictionary.mapValues { element in element.getValue() }
        } else {
            return self.value
        }
    }
}
