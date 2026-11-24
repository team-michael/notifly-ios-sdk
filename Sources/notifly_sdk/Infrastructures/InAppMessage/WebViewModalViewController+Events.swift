import SafariServices
import UIKit
import WebKit

@available(iOSApplicationExtension, unavailable)
extension WebViewModalViewController {

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
                reEligibleCondition: reEligibleCondition
            )
        {
            hideUntilData = [campaignID: hideUntil]
            if let main = try? Notifly.main {
                main.inAppMessageManager.userStateManager.updateUserCampaignHiddenUntilData(
                    userID: try? main.userManager.getNotiflyUserID(),
                    hideUntilData: [
                        campaignID: hideUntil
                    ]
                )
            }
            else {
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
                "campaign_id": notiflyCampaignID as Any,
                "notifly_message_id": notiflyMessageID as Any,
                "hide_until_data": hideUntilData as Any,
                "template_name": modalProps?.templateName ?? ""
            ] as [String: Any]
        notifly.trackingManager.trackInternalEvent(
            eventName: TrackingConstant.Internal.inAppMessageShown,
            eventParams: params
        )
        notifly.inAppMessageManager.dispatchInAppMessageEvent(
            eventName: TrackingConstant.Internal.inAppMessageShown,
            eventParams: params
        )
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notiflyInAppMessageEventHandler" {
            guard let notifly = try? Notifly.main else {
                Logger.error(
                    "Fail to Log In-App-Message Click Event: Notifly is not initialized yet. "
                )
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
                    "campaign_id": notiflyCampaignID as Any,
                    "notifly_message_id": notiflyMessageID as Any,
                    "notifly_extra_data": notiflyExtraData as Any
                ] as [String: Any]

            switch type {
            case "close":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageCloseButtonClicked,
                    eventParams: params
                )
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageCloseButtonClicked,
                    eventParams: params
                )
                dismissInAppMessage()
            case "main_button":
                handleMainButton(messageEventData: messageEventData, params: params, notifly: notifly)
            case "hide_in_app_message":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked,
                    eventParams: params
                )
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageDontShowAgainButtonClicked,
                    eventParams: params
                )
                dismissInAppMessage()
                hideInAppMessageUntilRequestedTime()
            case "survey_submit_button":
                notifly.trackingManager.trackInternalEvent(
                    eventName: TrackingConstant.Internal.inAppMessageSurveySubmitButtonClicked,
                    eventParams: params
                )
                notifly.inAppMessageManager.dispatchInAppMessageEvent(
                    eventName: TrackingConstant.Internal.inAppMessageSurveySubmitButtonClicked,
                    eventParams: params
                )
                dismissInAppMessage()
            default:
                return
            }
        }
    }

    private func handleMainButton(
        messageEventData: [String: Any],
        params: [String: Any],
        notifly: Notifly
    ) {
        if let urlString = messageEventData["link"] as? String,
            let url = URL(string: urlString)
        {
            let openMode = NotiflyLinkHelper.parseOpenMode(from: url)
            let cleanURL = NotiflyLinkHelper.stripNotiflyParams(from: url)
            var paramsWithLink = params
            paramsWithLink["link"] = cleanURL.absoluteString

            notifly.trackingManager.trackInternalEvent(
                eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                eventParams: paramsWithLink
            )
            notifly.inAppMessageManager.dispatchInAppMessageEvent(
                eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                eventParams: paramsWithLink
            )

            let scheme = cleanURL.scheme?.lowercased()
            if openMode == "in_app_browser",
                scheme == "http" || scheme == "https"
            {
                // Try forwarding an owned Universal Link directly to the app delegate.
                if NotiflyLinkHelper.isOwnUniversalLink(cleanURL) {
                    let currentScene = view.window?.windowScene
                    if NotiflyLinkHelper.openAsUniversalLink(cleanURL, in: currentScene) {
                        dismissInAppMessage()
                        return
                    }
                }
                // Use SFSafariViewController for external URLs and unhandled Universal Links.
                let presenter = presentingViewController
                dismissInAppMessage {
                    let safariVC = SFSafariViewController(url: cleanURL)
                    presenter?.present(safariVC, animated: true)
                }
            }
            else {
                UIApplication.shared.open(cleanURL)
                dismissInAppMessage()
            }
        }
        else {
            notifly.trackingManager.trackInternalEvent(
                eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                eventParams: params
            )
            notifly.inAppMessageManager.dispatchInAppMessageEvent(
                eventName: TrackingConstant.Internal.inAppMessageMainButtonClicked,
                eventParams: params
            )
            dismissInAppMessage()
        }
    }

    private func hideInAppMessageUntilRequestedTime() {
        if let templateName = modalProps?.templateName {
            let now = AppHelper.getCurrentTimestamp(unit: .second)
            var hideUntil: Int
            if let message = notiflyExtraData,
                let hideUntilInDays = message["hide_until_in_days"] as? Int,
                hideUntilInDays > 0
            {
                hideUntil = now + 24 * 3600 * hideUntilInDays
            }
            else {
                hideUntil = -1
            }
            let newProperty = "hide_in_app_message_until_" + templateName
            try? Notifly.main.userManager.setUserProperties(userProperties: [
                newProperty: hideUntil
            ])
        }
    }

    private func dismissInAppMessage(completion: (() -> Void)? = nil) {
        dismiss(animated: false, completion: completion)
    }
}
