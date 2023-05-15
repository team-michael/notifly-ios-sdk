import Foundation
import UIKit
import WebKit

class WebViewModalViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    static var openedInAppMessageCount: Int = 0
    var webView = FullScreenWKWebView()
    var notiflyCampaignID: String?
    var notiflyMessageID: String?
    var modalProps: [String: Any]?

    convenience init(url: URL?, notiflyCampaignID: String?, notiflyMessageID: String?, modalProps: [String: Any]?) throws {
        guard let url = url else {
            throw NotiflyError.unexpectedNil("URL is nil. Cannot create WebViewModalViewController.")
        }

        self.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen

        self.notiflyCampaignID = notiflyCampaignID
        self.notiflyMessageID = notiflyMessageID
        self.modalProps = modalProps
        webView.load(URLRequest(url: url))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "notiflyInAppMessageEventHandler")
        WebViewModalViewController.openedInAppMessageCount += 1

        if !setupUI() as Bool {
            dismissCTATapped()
            return
        }

        if let params = [
            "type": "message_event",
            "channel": "in-app-message",
            "campaign_id": notiflyCampaignID,
            "notifly_message_id": notiflyMessageID,
        ] as? [String: Any] {
            Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageShown, params: params)
        }
    }

    func setupUI() -> Bool {
        let screenSize: CGSize
        if let window = UIApplication.shared.keyWindow {
            screenSize = window.bounds.size
        } else {
            screenSize = UIScreen.main.bounds.size
        }

        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        if screenWidth == 0 || screenHeight == 0 {
            return false
        }

        guard let modalSize = CGSize(width: getViewWidth(modalProps: modalProps, screenWidth: screenWidth, screenHeight: screenHeight), height: getViewHeight(modalProps: modalProps, screenWidth: screenWidth, screenHeight: screenHeight)) as? CGSize else {
            return false
        }

        view.backgroundColor = .clear
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: modalSize.width),
            webView.heightAnchor.constraint(equalToConstant: modalSize.height),
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
        ])

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped)))

        return true
    }

    @objc
    private func dismissCTATapped() {
        dismiss(animated: false)
        WebViewModalViewController.openedInAppMessageCount -= 1
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
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

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notiflyInAppMessageEventHandler" {
            guard let body = message.body as? String,
                  let messageEventData = convertStringToJson(body) as [String: Any]? else { return }

            guard let type = messageEventData["type"] as? String,
                  let buttonName = messageEventData["button_name"] as? String else { return }
            let params = [
                "type": "message_event",
                "channel": "in-app-message",
                "campaign_id": notiflyCampaignID ?? "",
                "notifly_message_id": notiflyMessageID ?? "",
                "button_name": buttonName,
            ]

            switch type {
            case "close":
                Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageCloseButtonClicked, params: params)
                dismissCTATapped()

            case "main-button":
                Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageCloseButtonClicked, params: params)
                dismissCTATapped()

            case "hide_in_app_message":
                Notifly.main.trackingManager.trackInternalEvent(name: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked, params: params)
                dismissCTATapped()
            default:
                return
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

    internal func getViewWidth(modalProps: [String: Any]?, screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
        var viewWidth: CGFloat = 0.0

        if let width = modalProps?["width"] as? CGFloat {
            viewWidth = width
        } else if let widthVW = modalProps?["width_vw"] as? CGFloat {
            viewWidth = screenWidth * (widthVW / 100)
        } else if let widthVH = modalProps?["width_vh"] as? CGFloat, screenHeight != 0.0 {
            viewWidth = screenHeight * (widthVH / 100)
        } else {
            viewWidth = screenWidth
        }

        if let minWidth = modalProps?["min_width"] as? CGFloat, viewWidth < minWidth {
            viewWidth = minWidth
        }
        if let maxWidth = modalProps?["max_width"] as? CGFloat, viewWidth > maxWidth {
            viewWidth = maxWidth
        }

        return viewWidth
    }

    internal func getViewHeight(modalProps: [String: Any]?, screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
        var viewHeight: CGFloat = 0.0

        if let height = modalProps?["height"] as? CGFloat {
            viewHeight = height
        } else if let heightVH = modalProps?["height_vh"] as? CGFloat {
            viewHeight = screenHeight * (heightVH / 100)
        } else if let heightVW = modalProps?["height_vw"] as? CGFloat, screenWidth != 0.0 {
            viewHeight = screenWidth * (heightVW / 100)
        } else {
            viewHeight = screenHeight
        }

        if let minHeight = modalProps?["min_height"] as? CGFloat, viewHeight < minHeight {
            viewHeight = minHeight
        }
        if let maxHeight = modalProps?["max_height"] as? CGFloat, viewHeight > maxHeight {
            viewHeight = maxHeight
        }

        return viewHeight
    }
}

class FullScreenWKWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
