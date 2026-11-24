//
//  SSEMessage.swift
//  notifly-ios-sdk
//

import Foundation

enum SSEMessage {

    case connected
    case sync
    case event(name: String, eventParams: [String: Any]?)
    case shutdown(reconnectInMs: Int)
    case ttlExpired
    case unknown(rawType: String)
    case malformed(rawType: String)

    static func decode(type: String, data: String) -> SSEMessage {
        switch type {
        case "connected":
            return .connected
        case "sync":
            return .sync
        case "server-event":
            guard let json = parseJSON(data),
                let name = json["name"] as? String
            else {
                return .malformed(rawType: type)
            }
            let params = json["eventParams"] as? [String: Any]
            return .event(name: name, eventParams: params)
        case "shutdown":
            // Accept Int, Double, and NSNumber because the server may send either 1000 or 1000.0.
            let raw = parseJSON(data)?["reconnectInMs"]
            let ms: Int =
                (raw as? Int)
                ?? (raw as? NSNumber)?.intValue
                ?? (raw as? Double).map { Int($0) }
                ?? 0
            return .shutdown(reconnectInMs: max(ms, 0))
        case "ttl-expired":
            return .ttlExpired
        default:
            return .unknown(rawType: type)
        }
    }

    private static func parseJSON(_ data: String) -> [String: Any]? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }
}
