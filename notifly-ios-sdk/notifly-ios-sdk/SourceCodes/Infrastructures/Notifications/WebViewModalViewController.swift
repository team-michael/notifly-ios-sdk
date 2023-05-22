import Foundation
import UIKit
import WebKit

class WebViewModalViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    static var openedInAppMessageCount: Int = 0
    let webView = FullScreenWKWebView()
    var notiflyCampaignID: String?
    var notiflyMessageID: String?
    var notiflyExtraData: [String: AnyCodable]?
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
            guard let notifly = try? Notifly.main else {
                Logger.error("Fail to Log In-App-Message Shown Event: Notifly is not initialized yet. ")
                return
            }
            notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageShown, eventParams: params)
        }
    }

    func setupUI() -> Bool {
        guard let modalSize = getModalSize() as? CGSize, let modalPositionConstraint = getModalPositionConstraint() as? NSLayoutConstraint, let webViewLayer = getWebViewLayer(modalSize: modalSize) as? CALayer? else {
            return false
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        webView.layer.mask = webViewLayer
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped)))
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: modalSize.width),
            webView.heightAnchor.constraint(equalToConstant: modalSize.height),
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            modalPositionConstraint,
        ])

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
            extra_data: event.notifly_extra_data,
        }));
            });
        """
        webView.evaluateJavaScript(injectedJavaScript, completionHandler: nil)
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notiflyInAppMessageEventHandler" {
            guard let notifly = try? Notifly.main else {
                Logger.error("Fail to Log In-App-Message Click Event: Notifly is not initialized yet. ")
                return
            }
            guard let body = message.body as? String,
                  let messageEventData = convertStringToJson(body) as [String: Any]? else { return }

            guard let type = messageEventData["type"] as? String,
                  let buttonName = messageEventData["button_name"] as? String else { return }

            if let extraData = messageEventData["extra_data"] as? [String: Any] {
                var convertedExtraData: [String: AnyCodable] = [:]
                AppHelper.makeJsonCodable(extraData)?.forEach { convertedExtraData[$0] = $1
                }
                notiflyExtraData = convertedExtraData
            }

            let params = [
                "type": "message_event",
                "channel": "in-app-message",
                "button_name": buttonName,
                "campaign_id": notiflyCampaignID,
                "notifly_message_id": notiflyMessageID,
                "notifly_extra_data": notiflyExtraData,
            ] as [String: Any]

            switch type {
            case "close":
                notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageCloseButtonClicked, eventParams: params)
                dismissCTATapped()
            case "main_button":
                if let urlString = messageEventData["link"] as? String,
                   let url = URL(string: urlString)
                {
                    UIApplication.shared.open(url, options: [:]) { _ in
                        notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked, eventParams: params)
                    }
                } else {
                    notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked, eventParams: params)
                }
                dismissCTATapped()
            case "hide_in_app_message":
                notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked, eventParams: params)
                dismissCTATapped()
                if let modalProps = modalProps as? [String: Any],
                   let templateName = modalProps["template_name"] as? String,
                   let newProperty = "hide_in_app_message_" + templateName as? String
                {
                    try? Notifly.main.userManager.setUserProperties([newProperty: true])
                }
            case "survey_submit_button":
                notifly.trackingManager.trackInternalEvent(eventName: TrackingConstant.Internal.inAppMessageSurveySubmitButtonClicked, eventParams: params)
                dismissCTATapped()
            default:
                return
            }
        }
    }

    private func convertStringToJson(_ jsonString: String) -> [String: Any]? {
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                if let jsonDict = jsonObject as? [String: Any] {
                    return jsonDict
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    private func getViewWidth(modalProps: [String: Any]?, screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
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

    private func getViewHeight(modalProps: [String: Any]?, screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
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

    private func getModalSize() -> CGSize? {
        let screenSize: CGSize
        if let window = UIApplication.shared.keyWindow {
            screenSize = window.bounds.size
        } else {
            screenSize = UIScreen.main.bounds.size
        }

        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        if screenWidth == 0 || screenHeight == 0 {
            return nil
        }
        guard let modalSize = CGSize(width: getViewWidth(modalProps: modalProps, screenWidth: screenWidth, screenHeight: screenHeight), height: getViewHeight(modalProps: modalProps, screenWidth: screenWidth, screenHeight: screenHeight)) as? CGSize else {
            return nil
        }

        return modalSize
    }

    private func getModalPositionConstraint() -> NSLayoutConstraint? {
        if let modalProps = modalProps,
           let position = modalProps["position"] as? String,
           position == "bottom"
        {
            return view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        }

        return view.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
    }

    private func getWebViewLayer(modalSize: CGSize) -> CALayer? {
        guard let modalProps = modalProps,
              let tlRadius = (modalProps["borderTopLeftRadius"] ?? 0.0) as? CGFloat,
              let trRadius = (modalProps["borderTopRightRadius"] ?? 0.0) as? CGFloat,
              let blRadius = (modalProps["borderBottomLeftRadius"] ?? 0.0) as? CGFloat,
              let brRadius = (modalProps["borderBottomRightRadius"] ?? 0.0) as? CGFloat
        else {
            return nil
        }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: tlRadius, y: 0))
        path.addLine(to: CGPoint(x: modalSize.width - trRadius, y: 0))
        path.addArc(withCenter: CGPoint(x: modalSize.width - trRadius, y: trRadius), radius: trRadius, startAngle: -CGFloat.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: modalSize.width, y: modalSize.height - brRadius))
        path.addArc(withCenter: CGPoint(x: modalSize.width - brRadius, y: modalSize.height - brRadius), radius: brRadius, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: blRadius, y: modalSize.height))
        path.addArc(withCenter: CGPoint(x: blRadius, y: modalSize.height - blRadius), radius: blRadius, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: tlRadius))
        path.addArc(withCenter: CGPoint(x: tlRadius, y: tlRadius), radius: tlRadius, startAngle: CGFloat.pi, endAngle: -CGFloat.pi / 2, clockwise: true)
        path.close()

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        return maskLayer
    }
}

class FullScreenWKWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
