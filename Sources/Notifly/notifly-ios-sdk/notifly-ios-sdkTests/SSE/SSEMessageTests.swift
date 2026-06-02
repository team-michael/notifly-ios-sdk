//
//  SSEMessageTests.swift
//  notifly-ios-sdkTests
//

import XCTest
@testable import notifly_ios_sdk

final class SSEMessageTests: XCTestCase {

    // MARK: - simple types

    func test_connected_dataIgnored() {
        if case .connected = SSEMessage.decode(type: "connected", data: "{\"projectId\":\"x\"}") {
            return
        }
        XCTFail("expected .connected")
    }

    func test_sync_dataIgnored() {
        if case .sync = SSEMessage.decode(type: "sync", data: "{\"ts\":1}") {
            return
        }
        XCTFail("expected .sync")
    }

    func test_ttlExpired() {
        if case .ttlExpired = SSEMessage.decode(type: "ttl-expired", data: "{\"reason\":\"connection-ttl\"}") {
            return
        }
        XCTFail("expected .ttlExpired")
    }

    func test_unknown_type() {
        if case .unknown(let raw) = SSEMessage.decode(type: "weird", data: "") {
            XCTAssertEqual(raw, "weird")
        } else {
            XCTFail("expected .unknown")
        }
    }

    // MARK: - server-event

    func test_serverEvent_withNameAndEventParams() {
        let data = "{\"name\":\"order_completed\",\"eventParams\":{\"price\":1000}}"
        if case .event(let name, let params) = SSEMessage.decode(type: "server-event", data: data) {
            XCTAssertEqual(name, "order_completed")
            XCTAssertEqual(params?["price"] as? Int, 1000)
        } else {
            XCTFail("expected .event")
        }
    }

    func test_serverEvent_withoutEventParams() {
        let data = "{\"name\":\"x\"}"
        if case .event(let name, let params) = SSEMessage.decode(type: "server-event", data: data) {
            XCTAssertEqual(name, "x")
            XCTAssertNil(params)
        } else {
            XCTFail("expected .event")
        }
    }

    func test_serverEvent_missingName_isMalformed() {
        let data = "{\"eventParams\":{}}"
        if case .malformed(let raw) = SSEMessage.decode(type: "server-event", data: data) {
            XCTAssertEqual(raw, "server-event")
        } else {
            XCTFail("expected .malformed")
        }
    }

    func test_serverEvent_invalidJSON_isMalformed() {
        if case .malformed = SSEMessage.decode(type: "server-event", data: "not json") {
            return
        }
        XCTFail("expected .malformed")
    }

    // MARK: - shutdown

    func test_shutdown_withReconnectInMs() {
        let data = "{\"reason\":\"deployment\",\"reconnectInMs\":1500}"
        if case .shutdown(let ms) = SSEMessage.decode(type: "shutdown", data: data) {
            XCTAssertEqual(ms, 1500)
        } else {
            XCTFail("expected .shutdown(1500)")
        }
    }

    func test_shutdown_withoutReconnectInMs_defaultsToZero() {
        let data = "{\"reason\":\"x\"}"
        if case .shutdown(let ms) = SSEMessage.decode(type: "shutdown", data: data) {
            XCTAssertEqual(ms, 0)
        } else {
            XCTFail("expected .shutdown(0)")
        }
    }

    func test_shutdown_invalidJSON_defaultsToZero() {
        if case .shutdown(let ms) = SSEMessage.decode(type: "shutdown", data: "garbage") {
            XCTAssertEqual(ms, 0)
        } else {
            XCTFail("expected .shutdown(0)")
        }
    }

    func test_shutdown_negativeReconnectInMs_clampedToZero() {
        let data = "{\"reconnectInMs\":-100}"
        if case .shutdown(let ms) = SSEMessage.decode(type: "shutdown", data: data) {
            XCTAssertEqual(ms, 0)
        } else {
            XCTFail("expected .shutdown(0)")
        }
    }
}
