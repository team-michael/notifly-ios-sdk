//
//  SSELineParser.swift
//  notifly-ios-sdk
//
//  WHATWG "Server-sent events" 스펙에 따라 라인 입력을 누적해 SSEEvent 로 dispatch.
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
            // 스펙: U+0000 포함 id 는 무시.
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
        // 스펙: BOM 은 스트림 첫 라인에만 제거. 이후 라인의 U+FEFF 는 데이터로 보존.
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
