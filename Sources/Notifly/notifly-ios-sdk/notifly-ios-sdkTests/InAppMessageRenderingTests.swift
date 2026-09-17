import NotiflyCore
import WebKit
import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class InAppMessageRenderingTests: XCTestCase {
    func testRender_staticModes_completeSynchronouslyToPreserveCampaignOrder() {
        let renderer = InAppMessageRenderer(projectId: "", baseURL: "invalid", sdkVersion: "")
        for mode in [nil, "static", "unknown", "SSR", " ssr "] as [String?] {
            let data = makePopupData(mode: mode)
            var synchronousContent: InAppMessageContent?
            renderer.render(data: data, userID: "") { synchronousContent = $0 }

            XCTAssertEqual(synchronousContent, .url(data.url))
        }
    }

    func testRender_staticAndUnknownModes_preserveOriginalURL() {
        for mode in [nil, "static", "unknown"] as [String?] {
            let completed = expectation(description: "Static popup resolved")
            let data = makePopupData(mode: mode)
            let renderer = InAppMessageRenderer(projectId: "", baseURL: "invalid", sdkVersion: "")

            renderer.render(data: data, userID: "") { content in
                XCTAssertEqual(content, .url(data.url))
                completed.fulfill()
            }

            wait(for: [completed], timeout: 3)
        }
    }

    func testRender_invalidSsrConfiguration_doesNotFallBackToTemplate() {
        let completed = expectation(description: "Invalid SSR skipped")
        let renderer = InAppMessageRenderer(projectId: "", baseURL: "invalid", sdkVersion: "")

        renderer.render(data: makePopupData(), userID: "user-a") { content in
            XCTAssertNil(content)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 3)
    }

    func testWebView_staticContent_loadsOriginalURL() {
        let data = makePopupData(mode: nil)
        let controller = WebViewModalViewController()
        let webView = RecordingWebView()
        controller.webView = webView

        controller.loadContent(.url(data.url))

        XCTAssertEqual(webView.loadedURL, data.url)
        XCTAssertNil(webView.loadedHTML)
    }

    func testWebView_renderedContent_loadsHTMLWithOriginalBaseURL() throws {
        let data = makePopupData()
        let html = "<html><body>Personalized<img src='image.png'></body></html>"
        let controller = try WebViewModalViewController(
            notiflyInAppMessageData: data, content: .html(html, baseURL: data.url))
        let webView = RecordingWebView()
        removeScriptHandler(from: controller)
        controller.webView = webView
        defer { removeScriptHandler(from: controller) }

        drainMainQueue()

        XCTAssertEqual(webView.loadedHTML, html)
        XCTAssertEqual(webView.loadedBaseURL, data.url)
        XCTAssertNil(webView.loadedURL)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
    }

    private func removeScriptHandler(from controller: WebViewModalViewController) {
        controller.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "notiflyInAppMessageEventHandler")
    }
}

@available(iOSApplicationExtension, unavailable)
private final class RecordingWebView: FullScreenWKWebView {
    var loadedURL: URL?
    var loadedHTML: String?
    var loadedBaseURL: URL?

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedURL = request.url
        return nil
    }

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        loadedHTML = string
        loadedBaseURL = baseURL
        return nil
    }
}

@available(iOSApplicationExtension, unavailable)
private func makePopupData(mode: String? = "ssr") -> InAppMessageData {
    InAppMessageData(
        notiflyMessageId: "message-id", notiflyCampaignId: "campaign-id",
        modalProps: ModalProperties(properties: ["template_name": "test-template"])!,
        url: URL(string: "https://in-app-message.notifly.tech/templates/original.html")!,
        deadline: .now(), notiflyReEligibleCondition: nil,
        templateRenderingMode: mode, deviceID: "device-id",
        eventName: "purchase", eventParams: ["items": ["item-1"]]
    )
}
