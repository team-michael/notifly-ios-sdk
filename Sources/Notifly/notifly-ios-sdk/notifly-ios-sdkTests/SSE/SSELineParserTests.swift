//
//  SSELineParserTests.swift
//  notifly-ios-sdkTests
//
//  WHATWG SSE 스펙 핵심 룰을 라인 단위로 검증.
//

import XCTest
@testable import notifly_ios_sdk

final class SSELineParserTests: XCTestCase {

    // MARK: - 기본 dispatch

    func test_singleEvent_withTypeAndData_dispatchOnEmptyLine() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("event: sync"))
        XCTAssertNil(p.feed("data: {\"ts\":1}"))

        let event = p.feed("")
        XCTAssertEqual(event, SSEEvent(id: nil, type: "sync", data: "{\"ts\":1}"))
    }

    func test_dataOnly_typeDefaultsToMessage() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("data: hello"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "message", data: "hello"))
    }

    func test_emptyData_doesNotDispatch() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("event: sync"))
        XCTAssertNil(p.feed(""))   // data 없으면 dispatch X
    }

    func test_lineWithNoColon_treatedAsFieldNameWithEmptyValue() {
        let p = SSELineParser()
        // "data" 라인은 field=data, value="" → 빈 data 라인 1개 누적
        XCTAssertNil(p.feed("data"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "message", data: ""))
    }

    // MARK: - data 멀티라인

    func test_multipleDataLines_joinedWithNewline() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("data: line1"))
        XCTAssertNil(p.feed("data: line2"))
        XCTAssertNil(p.feed("data:line3"))   // 콜론 뒤 공백 없는 케이스
        XCTAssertEqual(
            p.feed(""),
            SSEEvent(id: nil, type: "message", data: "line1\nline2\nline3")
        )
    }

    // MARK: - comment / heartbeat

    func test_commentLine_ignoredAndDoesNotDispatch() {
        let p = SSELineParser()
        XCTAssertNil(p.feed(": heartbeat"))
        XCTAssertNil(p.feed(":"))
        XCTAssertNil(p.feed("data: hi"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "message", data: "hi"))
    }

    // MARK: - id 처리

    func test_idField_setsLastEventIdAndIsAttachedToDispatchedEvent() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("id: 42"))
        XCTAssertNil(p.feed("data: x"))
        let event = p.feed("")
        XCTAssertEqual(event?.id, "42")
        XCTAssertEqual(p.lastEventId, "42")
    }

    func test_idBufferPersists_acrossEventsWhenNotResent() {
        let p = SSELineParser()
        // 첫 이벤트: id 명시
        _ = p.feed("id: 7")
        _ = p.feed("data: a")
        let first = p.feed("")
        XCTAssertEqual(first?.id, "7")

        // 다음 이벤트: id 라인 없음 → 직전 buffer "7" 그대로 attach
        _ = p.feed("data: b")
        let second = p.feed("")
        XCTAssertEqual(second?.id, "7")
        XCTAssertEqual(p.lastEventId, "7")
    }

    func test_idEmptyValue_resetsBufferToEmptyString() {
        let p = SSELineParser()
        _ = p.feed("id: 5")
        _ = p.feed("data: a")
        _ = p.feed("")
        XCTAssertEqual(p.lastEventId, "5")

        // id: (빈 값) → buffer 를 "" 로 갱신
        _ = p.feed("id:")
        _ = p.feed("data: b")
        let event = p.feed("")
        XCTAssertEqual(event?.id, "")
        XCTAssertEqual(p.lastEventId, "")
    }

    func test_idWithNullByte_isIgnored() {
        let p = SSELineParser()
        _ = p.feed("id: ok")
        _ = p.feed("data: a")
        _ = p.feed("")
        XCTAssertEqual(p.lastEventId, "ok")

        // U+0000 포함 → 무시 (buffer 유지)
        _ = p.feed("id: bad\u{0000}value")
        _ = p.feed("data: b")
        let event = p.feed("")
        XCTAssertEqual(event?.id, "ok")
        XCTAssertEqual(p.lastEventId, "ok")
    }

    // MARK: - retry / unknown field

    func test_retryField_isIgnored() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("retry: 5000"))
        XCTAssertNil(p.feed("data: x"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "message", data: "x"))
    }

    func test_unknownField_isIgnored() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("custom: whatever"))
        XCTAssertNil(p.feed("data: x"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "message", data: "x"))
    }

    // MARK: - line ending / BOM

    func test_trailingCarriageReturn_isStripped() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("event: sync\r"))
        XCTAssertNil(p.feed("data: payload\r"))
        XCTAssertEqual(p.feed("\r"), SSEEvent(id: nil, type: "sync", data: "payload"))
    }

    func test_bomAtStart_isStripped() {
        let p = SSELineParser()
        XCTAssertNil(p.feed("\u{FEFF}event: sync"))
        XCTAssertNil(p.feed("data: x"))
        XCTAssertEqual(p.feed(""), SSEEvent(id: nil, type: "sync", data: "x"))
    }

    func test_bom_onlyStrippedFromFirstLine_preservedInDataValueAfter() {
        let p = SSELineParser()
        // 첫 라인의 BOM 은 제거.
        XCTAssertNil(p.feed("\u{FEFF}event: msg"))
        // 이후 라인의 U+FEFF 는 데이터 일부로 보존.
        XCTAssertNil(p.feed("data: \u{FEFF}value"))
        XCTAssertEqual(p.feed("")?.data, "\u{FEFF}value")
    }

    // MARK: - 콜론 뒤 공백 처리

    func test_singleLeadingSpace_isStripped() {
        let p = SSELineParser()
        _ = p.feed("data: x")  // " x" 가 아니라 "x"
        XCTAssertEqual(p.feed("")?.data, "x")
    }

    func test_multipleLeadingSpaces_onlyOneStripped() {
        let p = SSELineParser()
        _ = p.feed("data:  x")  // 첫 공백만 제거 → " x" 보존
        XCTAssertEqual(p.feed("")?.data, " x")
    }

    func test_noLeadingSpace_valuePreserved() {
        let p = SSELineParser()
        _ = p.feed("data:x")
        XCTAssertEqual(p.feed("")?.data, "x")
    }

    // MARK: - 통합 시나리오

    func test_typicalServerSentSequence() {
        let p = SSELineParser()
        // connected
        _ = p.feed(": stream opened")        // comment
        _ = p.feed("event: connected")
        _ = p.feed("data: {\"projectId\":\"abc\"}")
        let connected = p.feed("")
        XCTAssertEqual(connected?.type, "connected")

        // sync (with id)
        _ = p.feed("id: 42")
        _ = p.feed("event: sync")
        _ = p.feed("data: {}")
        let sync = p.feed("")
        XCTAssertEqual(sync, SSEEvent(id: "42", type: "sync", data: "{}"))

        // heartbeat
        _ = p.feed(": heartbeat")
        XCTAssertNil(p.feed(""))   // dispatch 시도하지만 data 비어 dispatch 안 됨

        // server-event with multiline data
        _ = p.feed("id: 43")
        _ = p.feed("event: server-event")
        _ = p.feed("data: {\"name\":\"order_completed\",")
        _ = p.feed("data:  \"eventParams\":{}}")
        let event = p.feed("")
        XCTAssertEqual(event?.id, "43")
        XCTAssertEqual(event?.type, "server-event")
        XCTAssertEqual(event?.data, "{\"name\":\"order_completed\",\n \"eventParams\":{}}")
    }
}
