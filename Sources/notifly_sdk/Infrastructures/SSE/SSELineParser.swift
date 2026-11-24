//
//  SSELineParser.swift
//  notifly-ios-sdk
//
// Accumulates lines and dispatches SSEEvent values using the WHATWG Server-Sent Events format.
//

import Foundation

final class SSELineParser {

    private var eventType: String?
    private var dataLines: [String] = []
    private var isFirstLine: Bool = true

    private(set) var lastEventId: String?

    func feed(_ rawLine: String) -> SSEEvent? {
        let line = stripLineEnding(rawLine)

        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let (field, value) = Self.splitFieldValue(line)
        switch field {
        case "id":
            // The stream format ignores event IDs containing U+0000.
            if !value.contains("\0") {
                lastEventId = value
            }
        case "event":
            eventType = value
        case "data":
            dataLines.append(value)
        case "retry":
            break
        default:
            break
        }
        return nil
    }

    private func dispatch() -> SSEEvent? {
        defer {
            eventType = nil
            dataLines.removeAll()
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(
            id: lastEventId,
            type: eventType ?? "message",
            data: dataLines.joined(separator: "\n")
        )
    }

    private func stripLineEnding(_ s: String) -> String {
        var result = s
        if result.hasSuffix("\r") {
            result.removeLast()
        }
        // Strip a BOM only from the first line; preserve later U+FEFF characters as data.
        if isFirstLine {
            if result.first == "\u{FEFF}" {
                result.removeFirst()
            }
            isFirstLine = false
        }
        return result
    }

    private static func splitFieldValue(_ line: String) -> (String, String) {
        guard let colonIdx = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let field = String(line[..<colonIdx])
        var valueStart = line.index(after: colonIdx)
        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }
        return (field, String(line[valueStart...]))
    }
}
