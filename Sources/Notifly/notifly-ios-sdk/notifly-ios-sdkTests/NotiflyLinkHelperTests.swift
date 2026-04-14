import XCTest
@testable import notifly_ios_sdk

class NotiflyLinkHelperTests: XCTestCase {

    // MARK: - parseOpenMode

    func testParseOpenMode_inAppBrowser() {
        let url = URL(string: "https://example.com?nf_open_mode=in_app_browser")!
        XCTAssertEqual(NotiflyLinkHelper.parseOpenMode(from: url), "in_app_browser")
    }

    func testParseOpenMode_noParam() {
        let url = URL(string: "https://example.com")!
        XCTAssertNil(NotiflyLinkHelper.parseOpenMode(from: url))
    }

    func testParseOpenMode_otherParams() {
        let url = URL(string: "https://example.com?foo=bar&nf_open_mode=in_app_browser&baz=qux")!
        XCTAssertEqual(NotiflyLinkHelper.parseOpenMode(from: url), "in_app_browser")
    }

    func testParseOpenMode_unknownValue() {
        let url = URL(string: "https://example.com?nf_open_mode=unknown")!
        XCTAssertEqual(NotiflyLinkHelper.parseOpenMode(from: url), "unknown")
    }

    // MARK: - stripNotiflyParams

    func testStripNotiflyParams_removesOpenMode() {
        let url = URL(string: "https://example.com?nf_open_mode=in_app_browser")!
        let stripped = NotiflyLinkHelper.stripNotiflyParams(from: url)
        XCTAssertEqual(stripped.absoluteString, "https://example.com")
        XCTAssertNil(stripped.query)
    }

    func testStripNotiflyParams_preservesOtherParams() {
        let url = URL(string: "https://example.com?foo=bar&nf_open_mode=in_app_browser&baz=qux")!
        let stripped = NotiflyLinkHelper.stripNotiflyParams(from: url)
        XCTAssertTrue(stripped.absoluteString.contains("foo=bar"))
        XCTAssertTrue(stripped.absoluteString.contains("baz=qux"))
        XCTAssertFalse(stripped.absoluteString.contains("nf_open_mode"))
    }

    func testStripNotiflyParams_noParams() {
        let url = URL(string: "https://example.com")!
        let stripped = NotiflyLinkHelper.stripNotiflyParams(from: url)
        XCTAssertEqual(stripped.absoluteString, "https://example.com")
    }

    func testStripNotiflyParams_noOpenModeParam() {
        let url = URL(string: "https://example.com?foo=bar")!
        let stripped = NotiflyLinkHelper.stripNotiflyParams(from: url)
        XCTAssertEqual(stripped.absoluteString, "https://example.com?foo=bar")
    }

    // MARK: - isOwnUniversalLink

    func testIsOwnUniversalLink_httpScheme() {
        // entitlements 읽기가 안 되는 테스트 환경에서는 항상 false
        let url = URL(string: "https://example.com/path")!
        let result = NotiflyLinkHelper.isOwnUniversalLink(url)
        // 테스트 바이너리에는 associated domains가 없으므로 false
        XCTAssertFalse(result)
    }

    func testIsOwnUniversalLink_customScheme() {
        let url = URL(string: "myapp://deeplink")!
        XCTAssertFalse(NotiflyLinkHelper.isOwnUniversalLink(url))
    }

    func testIsOwnUniversalLink_noScheme() {
        let url = URL(string: "example.com")!
        XCTAssertFalse(NotiflyLinkHelper.isOwnUniversalLink(url))
    }

    // MARK: - EntitlementsReader

    func testEntitlementsReader_readFromCurrentBinary() {
        // 현재 테스트 바이너리에서 entitlements 읽기 시도
        guard let execName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String,
              let execPath = Bundle.main.path(forResource: execName, ofType: nil)
        else {
            // 테스트 환경에 따라 바이너리 경로가 없을 수 있음
            return
        }

        // 크래시 없이 완료되면 성공 (entitlements가 없어도 throw만 하고 크래시는 안 함)
        do {
            let entitlements = try EntitlementsReader(execPath).readEntitlements()
            // entitlements가 있으면 dictionary여야 함
            XCTAssertTrue(type(of: entitlements) == [String: Any].self)
        } catch {
            // 테스트 바이너리에 코드 서명이 없을 수 있음 — 정상적인 실패
            XCTAssertTrue(error is EntitlementsReader.Error)
        }
    }

    func testEntitlementsReader_invalidPath() {
        XCTAssertThrowsError(try EntitlementsReader("/nonexistent/path")) { error in
            guard let readerError = error as? EntitlementsReader.Error else {
                XCTFail("Expected EntitlementsReader.Error")
                return
            }
            XCTAssertEqual(String(describing: readerError), String(describing: EntitlementsReader.Error.binaryOpeningError))
        }
    }

    // MARK: - Wildcard Domain Matching

    func testWildcardDomainMatching() {
        // isOwnUniversalLink 내부 로직과 동일한 매칭 테스트
        let domains = ["example.com", "*.wildcard.com"]

        func matches(host: String) -> Bool {
            domains.contains { domain in
                if domain.hasPrefix("*.") {
                    return host.hasSuffix(String(domain.dropFirst(1)))
                }
                return domain == host
            }
        }

        XCTAssertTrue(matches(host: "example.com"))
        XCTAssertFalse(matches(host: "sub.example.com"))
        XCTAssertTrue(matches(host: "sub.wildcard.com"))
        XCTAssertTrue(matches(host: "deep.sub.wildcard.com"))
        XCTAssertFalse(matches(host: "wildcard.com"))
        XCTAssertFalse(matches(host: "other.com"))
    }
}
