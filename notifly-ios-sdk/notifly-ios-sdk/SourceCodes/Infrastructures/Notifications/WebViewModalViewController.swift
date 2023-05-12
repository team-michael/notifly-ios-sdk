import Foundation
import UIKit
import WebKit

class WebViewModalViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let webviewModalSize = CGSize(width: 350, height: 400)

    static var openedInAppMessageCount: Int = 0
    let webView = WKWebView()
    var notiflyCampaignID: String?
    var notiflyMessageID: String?

    convenience init(url: URL?, notiflyCampaignID: String?, notiflyMessageID: String?) throws {
        guard let url = url else {
            throw NotiflyError.unexpectedNil("URL is nil. Cannot create WebViewModalViewController.")
        }
        self.init(nibName: nil, bundle: nil)
        webView.load(URLRequest(url: url))
        self.notiflyCampaignID = notiflyCampaignID
        self.notiflyMessageID = notiflyMessageID
        if let param = [
            "type": "message_event",
            "channel": "in-app-message",
            "campaign_id": notiflyCampaignID,
            "notifly_message_id": notiflyMessageID,
        ] as? [String: String?] {
            main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageShown, params: nil) // TODO: Add params
        }
        WebViewModalViewController.openedInAppMessageCount += 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "notiflyInAppMessageEventHandler")
    }

    func setupUI() {
        view.backgroundColor = .clear
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: webviewModalSize.width),
            webView.heightAnchor.constraint(equalToConstant: webviewModalSize.height),
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
        ])

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped)))
    }

    @objc
    private func dismissCTATapped() {
        dismiss(animated: true)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        // 페이지 로드가 완료된 후에 자바스크립트를 삽입할 수 있습니다.
        let injectedJavaScript = """
        const button_trigger = document.getElementById('notifly-button-trigger'); button_trigger.addEventListener('click', function(event){
        if (!event.notifly_button_click_type) return;
        window.webkit.messageHandlers.notiflyInAppMessageEventHandler.postMessage(JSON.stringify({
            type: event.notifly_button_click_type,
            button_name: event.notifly_button_name,
            link: event.notifly_button_click_link,
        }));
            });
        """

        webView.evaluateJavaScript(injectedJavaScript, completionHandler: nil)
    }

    // 웹페이지에서 iOS 앱으로 메시지가 전송되면 호출되는 메서드
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notiflyInAppMessageEventHandler" {
            guard let body = message.body as? String,
                  messageEventData = convertStringToJson(body) as [String: Any]? else { return }

            guard let type = messageEventData["type"] as? String,
                  let buttonName = messageEventData["button_name"] else { return }

            let params = [
                "type": "message_event",
                "channel": "in-app-message",
                "campaign_id": notiflyCampaignID ?? "",
                "notifly_message_id": notiflyMessageID ?? "",
                "button_name": buttonName,
            ]

            switch type {
            case "close":
                main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageCloseButtonClicked, params: params)
                dismissCTATapped()
                WebViewModalViewController.openedInAppMessageCount -= 1

            case "main-button":
                main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageCloseButtonClicked, params: params)
                dismissCTATapped()
                WebViewModalViewController.openedInAppMessageCount -= 1

            case "hide_in_app_message":
                main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked, params: params)
                dismissCTATapped()
                WebViewModalViewController.openedInAppMessageCount -= 1
            }
        }
    }

    internal func convertStringToJson(_ jsonString: String) -> [String: Any]? {
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                if let jsonDict = jsonObject as? [String: Any] {
                    return jsonDict
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
            }
        }
        return nil
    }
}
