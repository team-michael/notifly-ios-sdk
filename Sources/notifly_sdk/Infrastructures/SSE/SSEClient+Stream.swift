//
//  SSEClient+Stream.swift
//  notifly-ios-sdk
//

import Foundation

@available(iOSApplicationExtension, unavailable)
extension SSEClient {

    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = defaultHeartbeatTimeout
        config.timeoutIntervalForResource = 35 * 60
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldUsePipelining = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    internal static func splitSSELines<S: AsyncSequence>(_ bytes: S) -> AsyncThrowingStream<String, Error>
    where S.Element == UInt8 {
        AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    var buffer: [UInt8] = []
                    var prevWasCR = false
                    for try await byte in bytes {
                        if byte == 0x0A {
                            if prevWasCR {
                                prevWasCR = false
                                continue
                            }
                            continuation.yield(decodeSSELine(buffer))
                            buffer.removeAll(keepingCapacity: true)
                        }
                        else if byte == 0x0D {
                            continuation.yield(decodeSSELine(buffer))
                            buffer.removeAll(keepingCapacity: true)
                            prevWasCR = true
                        }
                        else {
                            prevWasCR = false
                            buffer.append(byte)
                        }
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decodeSSELine(_ bytes: [UInt8]) -> String {
        // SSE text replaces invalid UTF-8 sequences instead of dropping the line.
        return String(decoding: bytes, as: Unicode.UTF8.self)
    }
}
