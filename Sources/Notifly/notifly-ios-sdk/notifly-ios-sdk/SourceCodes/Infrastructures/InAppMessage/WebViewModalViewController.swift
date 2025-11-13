import Foundation
import UIKit
import WebKit

@available(iOSApplicationExtension, unavailable)
class WebViewModalViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
    WKUIDelegate
{
    private static let openedInAppMessageCountAccessQueue = DispatchQueue(
        label: "com.notifly.openedInAppMessageCountQueue")
    private static var _openedInAppMessageCount: Int = 0
    static var openedInAppMessageCount: Int {
        get {
            WebViewModalViewController.openedInAppMessageCountAccessQueue.sync {
                WebViewModalViewController._openedInAppMessageCount
            }
        }
        set {
            WebViewModalViewController.openedInAppMessageCountAccessQueue.sync {
                WebViewModalViewController._openedInAppMessageCount = newValue
            }
        }
    }

    var webView = FullScreenWKWebView()
    var notiflyCampaignID: String?
    var notiflyMessageID: String?
    var notiflyExtraData: [String: Any]?
    var notiflyReEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition?
    var modalProps: ModalProperties?

    convenience init(notiflyInAppMessageData: InAppMessageData) throws {
        self.init(nibName: nil, bundle: nil)
        view.isHidden = false
        modalPresentationStyle = .overFullScreen
        notiflyCampaignID = notiflyInAppMessageData.notiflyCampaignId
        notiflyMessageID = notiflyInAppMessageData.notiflyMessageId
        notiflyReEligibleCondition = notiflyInAppMessageData.notiflyReEligibleCondition
        modalProps = notiflyInAppMessageData.modalProps
        guard UIApplication.shared.canOpenURL(notiflyInAppMessageData.url) else {
            Logger.error("Fail to load in app message: invalid url.")
            throw NotiflyError.unexpectedNil(
                "Fail to load in app message: invalid url or Network issue.")
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.load(URLRequest(url: notiflyInAppMessageData.url))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(
            self, name: "notiflyInAppMessageEventHandler")
    }

    func setupUI() -> Bool {
        guard let modalSize = getModalSize() as? CGSize,
              let webViewLayer = getWebViewLayer(modalSize: modalSize) as? CALayer?
        else {
            return false
        }
        let modalPositionConstraint = getModalPositionConstraint() as NSLayoutConstraint

        webView.translatesAutoresizingMaskIntoConstraints = false
        let opacity = (modalProps?.backgroundOpacity as? CGFloat).map { max(0, min(1, $0)) } ?? 0.2
        view.backgroundColor = UIColor.black.withAlphaComponent(opacity)

        webView.layer.mask = webViewLayer

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        if let backgroundColorString = modalProps?.backgroundColor as? String,
           let backgroundColor = UIColor(hex: backgroundColorString)
        {
            webView.scrollView.backgroundColor = backgroundColor
        }

        if let shouldDismissCTATapped = modalProps?.dismissCTATapped,
           shouldDismissCTATapped
        {
            view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped)))
        }

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: modalSize.width),
            webView.heightAnchor.constraint(equalToConstant: modalSize.height),
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            modalPositionConstraint
        ])
        let shown = show()
        return shown
    }

    func show(animated: Bool = false, completion _: (() -> Void)? = nil) -> Bool {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
                  let topVC = window.topMostViewController,
                  !(self.isBeingPresented),
                  !(self.isBeingDismissed),
                  self.presentingViewController == nil
            else {
                WebViewModalViewController.openedInAppMessageCount = 0
                Logger.error("Fail to present in app message.")
                return
            }
            topVC.present(self, animated: animated)
        }
        return true
    }

    @objc
    private func dismissCTATapped() {
        dismiss(animated: false)
        WebViewModalViewController.openedInAppMessageCount = 0
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        webView.evaluateJavaScript(InAppMessageConstant.injectedJavaScript, completionHandler: nil)
        if !setupUI() as Bool {
            WebViewModalViewController.openedInAppMessageCount = 0
            return
        }
        view.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.view.isHidden = false
        }
        var hideUntilData: [String: Int]?
        if let campaignID = notiflyCampaignID,
           let reEligibleCondition = notiflyReEligibleCondition,
           let hideUntil = NotiflyHelper.calculateHideUntil(
               reEligibleCondition: reEligibleCondition)
        {
            hideUntilData = [campaignID: hideUntil]
            if let main = try? Notifly.main,
               let userStateManager = main.inAppMessageManager.userStateManager
               as? UserStateManager
            {
                userStateManager.updateUserCampaignHiddenUntilData(
                    userID: try? main.userManager.getNotiflyUserID(),
                    hideUntilData: [
                        campaignID: hideUntil
                    ])
            } else {
                Logger.error("UserStateManager manager is not exist.")
            }
        }

        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to Log In-App-Message Shown Event: Notifly is not initialized yet. ")
            return
        }
        let params =
            [
                "type": "message_event",
                "channel": InAppMessageConstant.inAppMessageChannel,
                "campaign_id": notiflyCampaignID,
                "notifly_message_id": notiflyMessageID,
                "hide_until_data": hideUntilData ?? nil,
                "template_name": modalProps?.templateName ?? ""
            ] as [String: Any]
        notifly.trackingManager.trackInternalEvent(
            eventName: TrackingConstant.Internal.inAppMessageShown, eventParams: params)
        notifly.inAppMessageManager.dispatchInAppMessageEvent(
            eventName: TrackingConstant.Internal.inAppMessageShown, eventParams: params)
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notiflyInAppMessageEventHandler" {
            guard let notifly = try? Notifly.main else {
                Logger.error(
                    "Fail to Log In-App-Message Click Event: Notifly is not initialized yet. ")
                return
            }

            guard let body = message.body as? String,
                  let messageEventData = NotiflyAnyCodable.parseJsonString(body) as [String: Any]?
            else {
                return
            }

            guard let type = messageEventData["type"] as? String,
                  let buttonName = messageEventData["button_name"] as? String
            else {
                return
            }

            if let extraData = messageEventData["extra_data"] as? [String: Any] {
                notiflyExtraData = extraData
            }

            let params =
                [
                    "type": "message_event",
                    "channel": InAppMessageConstant.inAppMessageChannel,
                    "button_name": buttonName,
                    "campaign_id": notiflyCampaignID,
                    "notifly_message_id": notiflyMessageID,
                    "notifly_extra_data": notiflyExtraData
                ] as [String: Any]

            switch type {
            case "close":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageCloseButtonClicked,
                    eventParams: params)
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageCloseButtonClicked,
                    eventParams: params)
                dismissCTATapped()
            case "main_button":
                if let urlString = messageEventData["link"] as? String,
                   let url = URL(string: urlString)
                {
                    UIApplication.shared.open(url, options: [:]) { _ in
                        var paramsWithLink = params
                        paramsWithLink["link"] = urlString
                        notifly.trackingManager.trackInternalEvent(
                            eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                            eventParams: paramsWithLink)
                        notifly.inAppMessageManager.dispatchInAppMessageEvent(
                            eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                            eventParams: paramsWithLink)
                        self.dismissCTATapped()
                    }
                } else {
                    notifly.trackingManager.trackInternalEvent(
                        eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                        eventParams: params)
                    notifly.inAppMessageManager.dispatchInAppMessageEvent(
                        eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                        eventParams: params)
                    dismissCTATapped()
                }
            case "hide_in_app_message":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked,
                    eventParams: params)
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked,
                    eventParams: params)
                dismissCTATapped()
                if let templateName = modalProps?.templateName {
                    let now = AppHelper.getCurrentTimestamp(unit: .second)
                    var hideUntil: Int
                    if let message = notiflyExtraData,
                       let hideUntilInDays = message["hide_until_in_days"] as? Int,
                       hideUntilInDays > 0
                    {
                        hideUntil = now + 24 * 3600 * hideUntilInDays
                    } else {
                        hideUntil = -1
                    }
                    let newProperty = "hide_in_app_message_until_" + templateName
                    try? Notifly.main.userManager.setUserProperties(userProperties: [
                        newProperty: hideUntil
                    ])
                }
            case "survey_submit_button":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageSurveySubmitButtonClicked,
                    eventParams: params)
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageSurveySubmitButtonClicked,
                    eventParams: params)
                dismissCTATapped()
            default:
                return
            }
        }
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

        var viewWidth: CGFloat = 0.0
        var viewHeight: CGFloat = 0.0

        if let width = modalProps?.width {
            viewWidth = width
        } else if let widthVW = modalProps?.width_vw {
            viewWidth = screenWidth * (widthVW / 100)
        } else if let widthVH = modalProps?.width_vh, screenHeight != 0.0 {
            viewWidth = screenHeight * (widthVH / 100)
        } else {
            viewWidth = screenWidth
        }

        if let minWidth = modalProps?.min_width, viewWidth < minWidth {
            viewWidth = minWidth
        }
        if let maxWidth = modalProps?.max_width, viewWidth > maxWidth {
            viewWidth = maxWidth
        }

        if let height = modalProps?.height {
            viewHeight = height
        } else if let heightVH = modalProps?.height_vh {
            viewHeight = screenHeight * (heightVH / 100)
        } else if let heightVW = modalProps?.height_vw, screenWidth != 0.0 {
            viewHeight = screenWidth * (heightVW / 100)
        } else {
            viewHeight = screenHeight
        }

        if let minHeight = modalProps?.min_height, viewHeight < minHeight {
            viewHeight = minHeight
        }
        if let maxHeight = modalProps?.max_height, viewHeight > maxHeight {
            viewHeight = maxHeight
        }

        let modalSize = CGSize(width: viewWidth, height: viewHeight)
        return modalSize
    }

    private func getModalPositionConstraint() -> NSLayoutConstraint {
        if let modalProps = modalProps,
           let position = modalProps.position as? String,
           position == "bottom"
        {
            return view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        }

        return view.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
    }

    private func getWebViewLayer(modalSize: CGSize) -> CALayer? {
        guard let modalProps = modalProps,
              let tlRadius = modalProps.borderTopLeftRadius,
              let trRadius = modalProps.borderTopRightRadius,
              let blRadius = modalProps.borderBottomLeftRadius,
              let brRadius = modalProps.borderBottomRightRadius
        else {
            return nil
        }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: tlRadius, y: 0))
        path.addLine(to: CGPoint(x: modalSize.width - trRadius, y: 0))
        path.addArc(
            withCenter: CGPoint(x: modalSize.width - trRadius, y: trRadius), radius: trRadius,
            startAngle: -CGFloat.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: modalSize.width, y: modalSize.height - brRadius))
        path.addArc(
            withCenter: CGPoint(x: modalSize.width - brRadius, y: modalSize.height - brRadius),
            radius: brRadius, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: blRadius, y: modalSize.height))
        path.addArc(
            withCenter: CGPoint(x: blRadius, y: modalSize.height - blRadius), radius: blRadius,
            startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: tlRadius))
        path.addArc(
            withCenter: CGPoint(x: tlRadius, y: tlRadius), radius: tlRadius, startAngle: CGFloat.pi,
            endAngle: -CGFloat.pi / 2, clockwise: true)
        path.close()

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        return maskLayer
    }
}

@available(iOSApplicationExtension, unavailable)
class FullScreenWKWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        scrollView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        scrollView.backgroundColor = .clear
    }

    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

private extension UIWindow {
    var topMostViewController: UIViewController? {
        return rootViewController?.topMostViewController
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMostViewController ?? nav
        }
        if let tab = self as? UITabBarController {
            if let selected = tab.selectedViewController {
                return selected.topMostViewController
            }
        }
        return self
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let r, g, b, a: CGFloat
        
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgba: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgba)

        switch hexSanitized.count {
        case 3:
            r = CGFloat((rgba >> 8) & 0xF) / 15.0
            g = CGFloat((rgba >> 4) & 0xF) / 15.0
            b = CGFloat(rgba & 0xF) / 15.0
            a = 1.0
        case 4:
            r = CGFloat((rgba >> 8) & 0xF) / 15.0
            g = CGFloat((rgba >> 4) & 0xF) / 15.0
            b = CGFloat(rgba & 0xF) / 15.0
            a = CGFloat((rgba >> 12) & 0xF) / 15.0
        case 6:
            r = CGFloat((rgba >> 16) & 0xFF) / 255.0
            g = CGFloat((rgba >> 8) & 0xFF) / 255.0
            b = CGFloat(rgba & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgba >> 16) & 0xFF) / 255.0
            g = CGFloat((rgba >> 8) & 0xFF) / 255.0
            b = CGFloat(rgba & 0xFF) / 255.0
            a = CGFloat((rgba >> 24) & 0xFF) / 255.0
        default:
            return nil
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
