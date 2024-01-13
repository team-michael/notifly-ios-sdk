//
//  InAppMessageManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Combine
import Dispatch
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class InAppMessageManager {
    let userStateManager: UserStateManager

    init(owner: String?) {
        userStateManager = UserStateManager(owner: owner)
    }

    func updateUserProperties(userID: String?, properties: [String: Any]) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        Notifly.keepGoingPub.sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in
                guard userID == self.userStateManager.owner else {
                    Logger.error("Fail to update client-side user state (user properties): owner mismatch")
                    return
                }
                self.userStateManager.userData.userProperties.merge(properties) { _, new in new }
            }
        )
        .store(in: &Notifly.cancellables)
    }

    func updateEventData(userID: String?, eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        guard userID == userStateManager.owner else {
            Logger.error("Fail to update client-side user state (event): owner mismatch")
            return
        }

        if var campaignsToTrigger = getCampaignsShouldBeTriggered(eventName: eventName, eventParams: eventParams)
        {
            campaignsToTrigger.sort(by: { $0.lastUpdatedTimestamp > $1.lastUpdatedTimestamp })
            for campaignToTrigger in campaignsToTrigger {
                if let notiflyInAppMessageData = prepareInAppMessageData(campaign: campaignToTrigger) {
                    showInAppMessage(notiflyInAppMessageData: notiflyInAppMessageData)
                }
            }
        }
        userStateManager.incrementEic(eventName: eventName, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys)
    }

    func updateHideCampaignUntilData(userID: String?, hideUntilData: [String: Int]) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        guard userID == userStateManager.owner else {
            Logger.error("Fail to update client-side user state (user campaign hidden until): owner mismatch")
            return
        }

        Notifly.keepGoingPub.sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in
                Logger.error("UPDATE HIDE CAMPAIGN")
                self.userStateManager.userData.campaignHiddenUntil.merge(hideUntilData) { _, new in new }
            }
        )
        .store(in: &Notifly.cancellables)
    }

    /* method for showing in-app message */
    private func getCampaignsShouldBeTriggered(eventName: String, eventParams: [String: Any]?) -> [Campaign]? {
        let campaignsToTrigger = userStateManager.campaignData.inAppMessageCampaigns
            .filter { isCampaignActive(campaign: $0) }
            .filter { matchTriggeringEventCondition(campaign: $0, eventName: eventName, eventParams: eventParams) }
            .filter { !isBlacklistTemplate(templateName: $0.message.modalProperties.templateName) }
            .filter { SegmentationHelper.isEntityOfSegment(campaign: $0, eventParams: eventParams, userData: userStateManager.userData, eventData: userStateManager.eventData) }

        if campaignsToTrigger.count == 0 {
            return nil
        }
        return campaignsToTrigger
    }

    private func isCampaignActive(campaign: Campaign) -> Bool {
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        let startTimestamp = campaign.campaignStart
        if let endTimestamp = campaign.campaignEnd {
            return now >= startTimestamp && now <= endTimestamp
        }
        return now >= startTimestamp
    }

    private func matchTriggeringEventCondition(campaign: Campaign, eventName: String, eventParams: [String: Any]?) -> Bool {
        if campaign.triggeringEvent != eventName {
            return false
        }

        if let paramsFilterCondition = campaign.triggeringEventFilters,
           !TriggeringEventFilter.matchFilterCondition(filters: paramsFilterCondition.filters, eventParams: eventParams)
        {
            return false
        }

        return true
    }

    private func isBlacklistTemplate(templateName: String) -> Bool {
        let outdatedPropertyKeyForBlacklist = "hide_in_app_message_" + templateName
        let propertyKeyForBlacklist = "hide_in_app_message_until_" + templateName
        if let hide = userStateManager.userData.userProperties[outdatedPropertyKeyForBlacklist] as? Bool {
            return hide
        }
        guard let hideUntil = userStateManager.userData.userProperties[propertyKeyForBlacklist] as? Int else {
            return false
        }

        if hideUntil == NotiflyReEligibleConditionEnum.defaultValue {
            return true
        }
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        if now <= hideUntil {
            return true
        } else {
            return false
        }

        return true
    }

    private func isHiddenCampaign(campaignID: String) -> Bool {
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        if let hideUntil = userStateManager.userData.campaignHiddenUntil[campaignID] {
            if hideUntil == NotiflyReEligibleConditionEnum.defaultValue {
                return true
            }
            if hideUntil >= now {
                return true
            }
        }
        return false
    }

    private func prepareInAppMessageData(campaign: Campaign) -> InAppMessageData? {
        let messageId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let campaignId = campaign.id
        let urlString = campaign.message.htmlURL
        let modalProperties = campaign.message.modalProperties
        let delay = DispatchTimeInterval.seconds(campaign.delay)
        let deadline = DispatchTime.now() + delay

        if let url = URL(string: urlString) {
            return InAppMessageData(notiflyMessageId: messageId, notiflyCampaignId: campaignId, modalProps: modalProperties, url: url, deadline: deadline, notiflyReEligibleCondition: campaign.reEligibleCondition)
        }
        return nil
    }

    private func showInAppMessage(notiflyInAppMessageData: InAppMessageData) {
        DispatchQueue.main.asyncAfter(deadline: notiflyInAppMessageData.deadline) {
            if let reEligibleCondition = notiflyInAppMessageData.notiflyReEligibleCondition {
                guard !self.isHiddenCampaign(campaignID: notiflyInAppMessageData.notiflyCampaignId) else {
                    return
                }
            }
            guard WebViewModalViewController.openedInAppMessageCount == 0 else {
                Logger.error("Already In App Message Opened. New In App Message Ignored.")
                return
            }
            WebViewModalViewController.openedInAppMessageCount = 1
            guard UIApplication.shared.applicationState == .active else {
                Logger.error("Due to being in a background state, in-app messages are being ignored.")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
            guard let vc = try? WebViewModalViewController(notiflyInAppMessageData: notiflyInAppMessageData) else {
                Logger.error("Error presenting in app message")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
        }
    }

    static func present(_ vc: UIViewController, animated: Bool = false, completion: (() -> Void)?) -> Bool {
        guard let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
              let topVC = window.topMostViewController,
              !(vc.isBeingPresented)
        else {
            Logger.error("Fail to present in app message.")
            return false
        }
        topVC.present(vc, animated: animated, completion: completion)
        return true
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
            return (tab.selectedViewController ?? self).topMostViewController
        }
        return self
    }
}
