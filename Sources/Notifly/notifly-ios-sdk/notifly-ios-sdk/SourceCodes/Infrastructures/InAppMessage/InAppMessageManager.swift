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
    private var eventListeners: [InAppMessageEventListener] = []
    private let renderer: InAppMessageRenderer
    private var scheduledWorkItems: [String: DispatchWorkItem] = [:]
    private let scheduleLock = NSLock()

    init(owner: String?, projectId: String, renderingBaseURL: String = NotiflyConstant.EndPoint.popupRenderingEndPoint) {
        userStateManager = UserStateManager(owner: owner)
        renderer = InAppMessageRenderer(
            projectId: projectId, baseURL: renderingBaseURL,
            sdkVersion: "notifly/ios/\(NotiflyHelper.getNativeSdkVersion())")
    }

    func mayTriggerInAppMessage(
        eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys _: [String]?
    ) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        checkCancellationConditions(eventName: eventName, eventParams: eventParams)

        if var campaignsToTrigger = getCampaignsShouldBeTriggered(
            eventName: eventName, eventParams: eventParams)
        {
            if campaignsToTrigger.isEmpty {
                return
            }
            campaignsToTrigger.sort(by: { $0.updatedAt > $1.updatedAt })
            for campaignToTrigger in campaignsToTrigger {
                if let notiflyInAppMessageData = prepareInAppMessageData(
                    campaign: campaignToTrigger, eventName: eventName, eventParams: eventParams)
                {
                    showInAppMessage(
                        userID: try? Notifly.main.userManager.getNotiflyUserID(),
                        notiflyInAppMessageData: notiflyInAppMessageData)
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

    private func prepareInAppMessageData(
        campaign: Campaign, eventName: String, eventParams: [String: Any]?
    ) -> InAppMessageData? {
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
                notiflyReEligibleCondition: campaign.reEligibleCondition,
                templateRenderingMode: campaign.message.templateRenderingMode,
                deviceID: AppHelper.getNotiflyDeviceID(), eventName: eventName, eventParams: eventParams)
        }
        return nil
    }

    private func showInAppMessage(userID: String?, notiflyInAppMessageData data: InAppMessageData) {
        guard let userID = userID else { return }
        let campaignId = data.notiflyCampaignId
        scheduleLock.lock()
        scheduledWorkItems.removeValue(forKey: campaignId)?.cancel()
        scheduleLock.unlock()

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem = workItem, !workItem.isCancelled else { return }
            guard self.canPresentInAppMessage(userID: userID, data: data) else {
                self.completeScheduledWorkItem(campaignId: campaignId, workItem: workItem)
                return
            }
            self.renderer.render(data: data, userID: userID) { [weak self] content in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.completeScheduledWorkItem(campaignId: campaignId, workItem: workItem),
                          !workItem.isCancelled, let content = content,
                          self.canPresentInAppMessage(userID: userID, data: data)
                    else { return }
                    WebViewModalViewController.openedInAppMessageCount = 1
                    guard (try? WebViewModalViewController(
                        notiflyInAppMessageData: data, content: content)) != nil
                    else {
                        WebViewModalViewController.openedInAppMessageCount = 0
                        Logger.error("Error presenting in app message")
                        return
                    }
                }
            }
        }

        guard let workItem = workItem else { return }
        scheduleLock.lock()
        scheduledWorkItems[campaignId] = workItem
        scheduleLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: data.deadline, execute: workItem)
    }

    /// Applies the existing display checks before and after the asynchronous render request.
    private func canPresentInAppMessage(userID: String, data: InAppMessageData) -> Bool {
        guard !Notifly.inAppMessageDisabled,
              userID == (try? Notifly.main.userManager.getNotiflyUserID()),
              UIApplication.shared.applicationState == .active,
              WebViewModalViewController.openedInAppMessageCount == 0
        else { return false }
        let userData = userStateManager.userData
        if data.notiflyReEligibleCondition != nil,
           isHiddenCampaign(campaignID: data.notiflyCampaignId, userData: userData) { return false }
        return !isHiddenTemplate(templateName: data.modalProps.templateName, userData: userData)
    }

    /// Removes only this request, leaving a newer request for the same campaign untouched.
    @discardableResult
    private func completeScheduledWorkItem(campaignId: String, workItem: DispatchWorkItem) -> Bool {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        guard scheduledWorkItems[campaignId] === workItem else { return false }
        scheduledWorkItems.removeValue(forKey: campaignId)
        return true
    }

    func getScheduledCampaignIds() -> [String] {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        return Array(scheduledWorkItems.keys)
    }

    func descheduleInAppMessage(campaignId: String) {
        scheduleLock.lock()
        let item = scheduledWorkItems.removeValue(forKey: campaignId)
        scheduleLock.unlock()
        item?.cancel()
    }

    private func checkCancellationConditions(eventName: String, eventParams: [String: Any]?) {
        let scheduledIds = getScheduledCampaignIds()
        if scheduledIds.isEmpty { return }

        let campaigns = userStateManager.getInAppMessageCampaigns()
        for campaignId in scheduledIds {
            guard let campaign = campaigns.first(where: { $0.id == campaignId }),
                  let cancellationConditions = campaign.cancellationConditions
            else { continue }

            guard cancellationConditions.match(eventName: eventName) else { continue }

            if let filters = campaign.cancellationEventFilters,
               !TriggeringEventFilter.matchFilterCondition(
                   filters: filters.filters, eventParams: eventParams) {
                continue
            }

            descheduleInAppMessage(campaignId: campaignId)
        }
    }

    func addEventListener(_ listener: @escaping InAppMessageEventListener) {
        eventListeners.append(listener)
    }

    func removeAllEventListeners() {
        eventListeners.removeAll()
    }

    func dispatchInAppMessageEvent(eventName: String, eventParams: [String: Any]?) {
        for listener in eventListeners {
            listener(eventName, eventParams)
        }
    }
}

public typealias InAppMessageEventListener = (String, [String: Any]?) -> Void
