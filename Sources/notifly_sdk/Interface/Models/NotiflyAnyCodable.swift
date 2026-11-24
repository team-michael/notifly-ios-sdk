import Foundation

/// Encodes and decodes the JSON-compatible values used by Notifly payloads.
///
/// Supported values are `nil`, `Bool`, `Int`, `Double`, `String`, arrays of optional
/// supported values, and string-keyed dictionaries of optional supported values.
/// Nested values are processed recursively. Arbitrary model objects are not encoded
/// merely because they conform to `Encodable`.
public struct NotiflyAnyCodable: Codable {

    private var value: Any?

    /// Wraps a value for subsequent encoding without validating it immediately.
    ///
    /// - Parameter value: The JSON-compatible value to wrap, or `nil` to encode JSON
    ///   null. Unsupported values are reported when `encode(to:)` is called.
    public init(_ value: Any?) {
        self.value = value
    }

    /// Decodes a supported value from a single-value container.
    ///
    /// Decoding checks null, booleans, integers, floating-point numbers, strings,
    /// arrays, and dictionaries in that order. Array and dictionary members use
    /// the same recursive decoding behavior.
    ///
    /// - Parameter decoder: The decoder positioned at the value to read.
    /// - Throws: A decoder error if a single-value container cannot be obtained, or
    ///   `DecodingError.dataCorrupted` if none of the supported forms can be decoded.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        }
        else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        }
        else if let intValue = try? container.decode(Int.self) {
            value = intValue
        }
        else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        }
        else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        }
        else if let arrayValue = try? container.decode([NotiflyAnyCodable].self) {
            value = arrayValue.map { $0.value }
        }
        else if let dictionaryValue = try? container.decode([String: NotiflyAnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        }
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    /// Encodes the wrapped value, recursively encoding arrays and dictionaries.
    ///
    /// A wrapped `nil` is encoded as JSON null. Values that do not match a supported
    /// runtime type fail instead of being converted to a string or silently omitted.
    ///
    /// - Parameter encoder: The encoder receiving the wrapped value.
    /// - Throws: `EncodingError.invalidValue` for an unsupported value, including one
    ///   nested in an array or dictionary, or an error reported by the encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let value = value else {
            try container.encodeNil()
            return
        }
        if let boolValue = value as? Bool {
            try container.encode(boolValue)
        }
        else if let intValue = value as? Int {
            try container.encode(intValue)
        }
        else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        }
        else if let stringValue = value as? String {
            try container.encode(stringValue)
        }
        else if let arrayValue = value as? [Any?] {
            let encodableArray = arrayValue.map { NotiflyAnyCodable($0) }
            try container.encode(encodableArray)
        }
        else if let dictionaryValue = value as? [String: Any?] {
            let encodableDictionary = dictionaryValue.mapValues { NotiflyAnyCodable($0) }
            try container.encode(encodableDictionary)
        }
        else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type"
                )
            )
        }
    }

    /// Parses a JSON string whose top-level value is an object.
    ///
    /// The input is converted to UTF-8 and decoded through `NotiflyAnyCodable`.
    /// A valid JSON array or scalar is not returned by this object-only helper.
    /// Parsing errors are converted to `nil` rather than propagated to the caller.
    ///
    /// - Parameter jsonString: The JSON object text to parse.
    /// - Returns: The decoded string-keyed dictionary, or `nil` if UTF-8 conversion,
    ///   JSON decoding, or conversion to `[String: Any]` fails.
    public static func parseJsonString(_ jsonString: String) -> [String: Any]? {
        let decoder = JSONDecoder()
        if let jsonData = jsonString.data(using: .utf8),
            let decodedData = try? decoder.decode(
                NotiflyAnyCodable.self,
                from: jsonData
            ),
            let value = decodedData.value as? [String: Any]
        {
            return value
        }
        return nil
    }

}
