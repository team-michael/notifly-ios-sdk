//
//  SSEByteLineSplitterTests.swift
//  notifly-ios-sdkTests
//
//  WHATWG SSE spec 의 line-splitting (LF / CR / CRLF) + 빈 라인 yield 검증.
//  LaunchDarkly swift-eventsource 의 UTF8LineParserTests 케이스를 미러링.
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class SSEByteLineSplitterTests: XCTestCase {

    // MARK: - Helpers

    private func split(_ bytes: [UInt8]) async throws -> [String] {
        let source = AsyncStream<UInt8> { continuation in
            for b in bytes { continuation.yield(b) }
            continuation.finish()
        }
        var lines: [String] = []
        for try await line in SSEClient.splitSSELines(source) {
            lines.append(line)
        }
        return lines
    }

    private func split(_ s: String) async throws -> [String] {
        try await split(Array(s.utf8))
    }

    // MARK: - 기본 terminator

    func test_lfOnly_yieldsSingleEmptyLine() async throws {
        let out = try await split("\n")
        XCTAssertEqual(out, [""])
    }

    func test_crOnly_yieldsSingleEmptyLine() async throws {
        let out = try await split("\r")
        XCTAssertEqual(out, [""])
    }

    func test_crlf_yieldsSingleEmptyLine() async throws {
        let out = try await split("\r\n")
        XCTAssertEqual(out, [""])
    }

    func test_singleLine_lf() async throws {
        let out = try await split("hello\n")
        XCTAssertEqual(out, ["hello"])
    }

    func test_singleLine_cr() async throws {
        let out = try await split("hello\r")
        XCTAssertEqual(out, ["hello"])
    }

    func test_singleLine_crlf() async throws {
        let out = try await split("hello\r\n")
        XCTAssertEqual(out, ["hello"])
    }

    // MARK: - EOF discard (WHATWG: pending data must be discarded)

    func test_unterminatedTail_isDiscarded() async throws {
        let out = try await split("hello")
        XCTAssertEqual(out, [])
    }

    func test_terminatedThenUnterminated_yieldsOnlyTerminated() async throws {
        let out = try await split("a\nbcd")
        XCTAssertEqual(out, ["a"])
    }

    // MARK: - mixed line endings

    func test_mixedLineEndings_inSingleStream() async throws {
        let out = try await split("a\nb\r\nc\rd\n")
        XCTAssertEqual(out, ["a", "b", "c", "d"])
    }

    // MARK: - 연속 blank line — SSE event terminator 핵심 케이스

    func test_consecutiveLF_yieldsMultipleBlankLines() async throws {
        let out = try await split("\n\n\n")
        XCTAssertEqual(out, ["", "", ""])
    }

    func test_consecutiveCRLF_yieldsMultipleBlankLines() async throws {
        let out = try await split("\r\n\r\n")
        XCTAssertEqual(out, ["", ""])
    }

    func test_blankLineBetweenContent() async throws {
        let out = try await split("a\n\nb\n")
        XCTAssertEqual(out, ["a", "", "b"])
    }

    func test_sseEventBlock_endsWithBlankLine() async throws {
        // 우리가 고치는 핵심 시나리오 — server 가 보낸 event terminator 가 SDK 까지 보존.
        let out = try await split("event: sync\ndata: {}\n\n")
        XCTAssertEqual(out, ["event: sync", "data: {}", ""])
    }

    // MARK: - CR 직후 비-LF byte

    func test_crFollowedByText_treatsCRAsTerminator() async throws {
        // \r 직후 text → \r 이 line terminator 로 작동, 'b' 는 다음 라인 시작
        let out = try await split("a\rb\n")
        XCTAssertEqual(out, ["a", "b"])
    }

    func test_crFollowedByCR_eachIsTerminator() async throws {
        let out = try await split("a\r\rb\n")
        XCTAssertEqual(out, ["a", "", "b"])
    }

    func test_lfFollowedByCR_eachIsTerminator() async throws {
        // \n 다음 \r — prevWasCR 가 set 되지 않은 상태라 \r 가 독립적 terminator
        let out = try await split("a\n\rb\n")
        XCTAssertEqual(out, ["a", "", "b"])
    }

    // MARK: - unicode 보존

    func test_unicodeContent_preserved() async throws {
        let out = try await split("안녕하세요\n")
        XCTAssertEqual(out, ["안녕하세요"])
    }

    func test_emojiContent_preserved() async throws {
        let out = try await split("hi 🚀\n")
        XCTAssertEqual(out, ["hi 🚀"])
    }

    func test_diacritics_preserved() async throws {
        let out = try await split("café\n")
        XCTAssertEqual(out, ["café"])
    }

    // MARK: - 통합 SSE 시나리오 — server 가 실제 보내는 형태

    func test_realisticSSEEventStream() async throws {
        // 두 개의 event block (connected, sync) + heartbeat comment.
        // 각 블록은 blank line 으로 종료된다. (Swift multiline literal 은 closing """ 직전의
        // 줄바꿈을 자동 제거하므로 마지막 terminator 는 명시적으로 \n 추가한다.)
        let stream = "event: connected\n"
            + "data: {\"projectId\":\"abc\"}\n"
            + "\n"
            + "id: 42\n"
            + "event: sync\n"
            + "data: {}\n"
            + "\n"
            + ": heartbeat\n"
            + "\n"
        let out = try await split(stream)
        XCTAssertEqual(out, [
            "event: connected",
            "data: {\"projectId\":\"abc\"}",
            "",
            "id: 42",
            "event: sync",
            "data: {}",
            "",
            ": heartbeat",
            "",
        ])
    }
}
