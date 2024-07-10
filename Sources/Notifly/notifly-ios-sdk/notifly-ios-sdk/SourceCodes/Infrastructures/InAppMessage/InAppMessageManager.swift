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

    func mayTriggerInAppMessage(
        eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys _: [String]?
    ) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        if var campaignsToTrigger = getCampaignsShouldBeTriggered(
            eventName: eventName, eventParams: eventParams)
        {
            if campaignsToTrigger.isEmpty {
                return
            }
            campaignsToTrigger.sort(by: { $0.updatedAt > $1.updatedAt })
            for campaignToTrigger in campaignsToTrigger {
                if let notiflyInAppMessageData = prepareInAppMessageData(
                    campaign: campaignToTrigger)
                {
                    showInAppMessage(
                        userID: try? Notifly.main.userManager.getNotiflyUserID(),
                        notiflyInAppMessageData: notiflyInAppMessageData
                    )
                }
            }
        }
    }

    /* method for showing in-app message */
    private func getCampaignsShouldBeTriggered(eventName: String, eventParams: [String: Any]?)
        -> [Campaign]?
    {
        let candidateCampaigns = userStateManager.getInAppMessageCampaigns()
        if candidateCampaigns.isEmpty {
            return []
        }
        let campaignsToTrigger =
            candidateCampaigns
            .filter {
                isCampaignActive(campaign: $0)
            }
            .filter {
                matchTriggeringConditions(campaign: $0, eventName: eventName)
            }
            .filter {
                matchTriggeringFilters(campaign: $0, eventName: eventName, eventParams: eventParams)
            }
            .filter {
                let currentUserData: UserData = userStateManager.userData
                let currentEventData: EventData = userStateManager.eventData
                return SegmentationHelper.isEntityOfSegment(
                    campaign: $0, eventParams: eventParams, userData: currentUserData,
                    eventData: currentEventData)
            }

        if campaignsToTrigger.isEmpty {
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

    private func matchTriggeringConditions(campaign: Campaign, eventName: String) -> Bool {
        return campaign.triggeringConditions.match(eventName: eventName)
    }

    private func matchTriggeringFilters(
        campaign: Campaign, eventName _: String, eventParams: [String: Any]?
    ) -> Bool {
        if let paramsFilterCondition = campaign.triggeringEventFilters,
            !TriggeringEventFilter.matchFilterCondition(
                filters: paramsFilterCondition.filters, eventParams: eventParams)
        {
            return false
        }

        return true
    }

    private func isHiddenTemplate(templateName: String, userData: UserData) -> Bool {
        let outdatedKey = "hide_in_app_message_" + templateName
        let key = "hide_in_app_message_until_" + templateName

        if let hide = userData.userProperties[outdatedKey] as? Bool {
            return hide
        }
        guard let hideUntil = userData.userProperties[key] as? Int else {
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
    }

    private func isHiddenCampaign(campaignID: String, userData: UserData) -> Bool {
        if let hideUntil = userData.campaignHiddenUntil[campaignID] {
            let now = AppHelper.getCurrentTimestamp(unit: .second)
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
            return InAppMessageData(
                notiflyMessageId: messageId, notiflyCampaignId: campaignId,
                modalProps: modalProperties, url: url, deadline: deadline,
                notiflyReEligibleCondition: campaign.reEligibleCondition)
        }
        return nil
    }

    private func showInAppMessage(
        userID: String?,
        notiflyInAppMessageData: InAppMessageData
    ) {
        guard let userID = userID else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: notiflyInAppMessageData.deadline) {
            guard let currentUserID = try? Notifly.main.userManager.getNotiflyUserID(),
                userID == currentUserID
            else {
                Logger.error("Skip to present in app message schedule: user id is changed.")
                return
            }

            let currentUserData = self.userStateManager.userData
            if let reEligibleCondition = notiflyInAppMessageData.notiflyReEligibleCondition {
                guard
                    !self.isHiddenCampaign(
                        campaignID: notiflyInAppMessageData.notiflyCampaignId,
                        userData: currentUserData)
                else {
                    return
                }
            }

            guard
                !self.isHiddenTemplate(
                    templateName: notiflyInAppMessageData.modalProps.templateName,
                    userData: currentUserData)
            else {
                return
            }
            6
            guard WebViewModalViewController.openedInAppMessageCount == 0 else {
                Logger.error("Already In App Message Opened. New In App Message Ignored.")
                return
            }

            WebViewModalViewController.openedInAppMessageCount = 1
            guard UIApplication.shared.applicationState == .active else {
                Logger.error(
                    "Due to being in a background state, in-app messages are being ignored.")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
            guard
                let vc = try? WebViewModalViewController(
                    notiflyInAppMessageData: notiflyInAppMessageData)
            else {
                Logger.error("Error presenting in app message")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
        }
    }
}
